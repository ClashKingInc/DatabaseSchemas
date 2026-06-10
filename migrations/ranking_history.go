//go:build ignore

// Backfill Mongo ranking_history snapshots into Timescale leaderboard_snapshot_items.
//
// This file intentionally lives outside the normal application packages. Because
// clashking_schemas has no go.mod, run it from a module that already has the
// MongoDB and pgx dependencies, for example:
//
//	cd /Users/matthewanderson/PycharmProjects/clashking_tracking
//	TIMESCALE_URL='postgres://...' go run /Users/matthewanderson/GolandProjects/clashking_schemas/migrations/ranking_history.go \
//	  --env-file /Users/matthewanderson/PycharmProjects/clashking_api/.env
//
// Use --dry-run --limit-docs 1 for a quick source-shape smoke test.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
)

const sourceDatabase = "ranking_history"

var defaultCollections = []string{
	"player_trophies",
	"clan_trophies",
	"clan_versus_trophies",
	"player_versus_trophies",
	"capital",
}

type config struct {
	EnvFile      string
	MongoURL     string
	TimescaleURL string
	Collections  []string
	BatchRows    int
	LimitDocs    int64
	DryRun       bool
}

type snapshotRow struct {
	Kind       string
	LocationID string
	Date       time.Time
	Tag        string
	Name       string
	Rank       int
	Data       string
}

func main() {
	if err := run(context.Background(), parseConfig()); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func parseConfig() config {
	var rawCollections string
	cfg := config{}
	flag.StringVar(&cfg.EnvFile, "env-file", "", "optional .env file, such as clashking_api/.env")
	flag.StringVar(&cfg.MongoURL, "mongo-url", "", "Mongo connection string; defaults to STATS_MONGODB then STATIC_MONGODB")
	flag.StringVar(&cfg.TimescaleURL, "timescale-url", "", "Postgres/Timescale URL; defaults to TIMESCALE_URL then DATABASE_URL")
	flag.StringVar(&rawCollections, "collections", strings.Join(defaultCollections, ","), "comma-separated ranking_history collections to migrate")
	flag.IntVar(&cfg.BatchRows, "batch-rows", 50000, "rows per Timescale upsert batch")
	flag.Int64Var(&cfg.LimitDocs, "limit-docs", 0, "optional per-collection document limit for smoke tests")
	flag.BoolVar(&cfg.DryRun, "dry-run", false, "read Mongo and count rows without writing Timescale")
	flag.Parse()

	for _, collection := range strings.Split(rawCollections, ",") {
		collection = strings.TrimSpace(collection)
		if collection != "" {
			cfg.Collections = append(cfg.Collections, collection)
		}
	}
	return cfg
}

func run(ctx context.Context, cfg config) error {
	env, err := loadEnv(cfg.EnvFile)
	if err != nil {
		return err
	}
	if cfg.MongoURL == "" {
		cfg.MongoURL = firstNonEmpty(env["STATS_MONGODB"], env["STATIC_MONGODB"], os.Getenv("STATS_MONGODB"), os.Getenv("STATIC_MONGODB"))
	}
	if cfg.TimescaleURL == "" {
		cfg.TimescaleURL = firstNonEmpty(env["TIMESCALE_URL"], env["DATABASE_URL"], os.Getenv("TIMESCALE_URL"), os.Getenv("DATABASE_URL"))
	}
	if cfg.MongoURL == "" {
		return errors.New("missing Mongo URL; set STATS_MONGODB, STATIC_MONGODB, or --mongo-url")
	}
	if cfg.TimescaleURL == "" && !cfg.DryRun {
		return errors.New("missing Timescale URL; set TIMESCALE_URL, DATABASE_URL, or --timescale-url")
	}
	if len(cfg.Collections) == 0 {
		return errors.New("at least one collection is required")
	}
	if cfg.BatchRows <= 0 {
		return errors.New("--batch-rows must be greater than zero")
	}

	mongoClient, err := mongo.Connect(options.Client().ApplyURI(cfg.MongoURL).SetCompressors([]string{"snappy"}))
	if err != nil {
		return err
	}
	defer func() { _ = mongoClient.Disconnect(ctx) }()

	var pool *pgxpool.Pool
	if !cfg.DryRun {
		pool, err = pgxpool.New(ctx, cfg.TimescaleURL)
		if err != nil {
			return err
		}
		defer pool.Close()
	}

	source := mongoClient.Database(sourceDatabase)
	var totalDocs, totalRows int64
	for _, collection := range cfg.Collections {
		docsSeen, rowsWritten, err := migrateCollection(ctx, source, pool, collection, cfg)
		if err != nil {
			return fmt.Errorf("%s: %w", collection, err)
		}
		totalDocs += docsSeen
		totalRows += rowsWritten
		fmt.Printf("%s: scanned_docs=%d rows=%d\n", collection, docsSeen, rowsWritten)
	}
	fmt.Printf("done: scanned_docs=%d rows=%d\n", totalDocs, totalRows)
	return nil
}

func migrateCollection(
	ctx context.Context,
	db *mongo.Database,
	pool *pgxpool.Pool,
	collectionName string,
	cfg config,
) (int64, int64, error) {
	findOptions := options.Find().
		SetSort(bson.D{{Key: "date", Value: 1}, {Key: "location", Value: 1}}).
		SetNoCursorTimeout(true).
		SetBatchSize(1000)
	if cfg.LimitDocs > 0 {
		findOptions.SetLimit(cfg.LimitDocs)
	}

	collection := db.Collection(collectionName)
	cursor, err := collection.Find(ctx, bson.D{}, findOptions)
	if err != nil {
		return 0, 0, err
	}
	defer cursor.Close(ctx)

	batch := make(map[string]snapshotRow, cfg.BatchRows)
	var docsSeen, rowsWritten int64
	for cursor.Next(ctx) {
		var doc bson.M
		if err := cursor.Decode(&doc); err != nil {
			return docsSeen, rowsWritten, err
		}
		docsSeen++
		for _, row := range snapshotRows(collectionName, doc) {
			batch[rowKey(row)] = row
			if len(batch) >= cfg.BatchRows {
				written, err := flushRows(ctx, pool, batch, cfg.DryRun)
				if err != nil {
					return docsSeen, rowsWritten, err
				}
				rowsWritten += written
				batch = make(map[string]snapshotRow, cfg.BatchRows)
			}
		}
		if docsSeen%1000 == 0 {
			fmt.Printf("%s: scanned_docs=%d rows=%d\n", collectionName, docsSeen, rowsWritten)
		}
	}
	if err := cursor.Err(); err != nil {
		return docsSeen, rowsWritten, err
	}
	if len(batch) > 0 {
		written, err := flushRows(ctx, pool, batch, cfg.DryRun)
		if err != nil {
			return docsSeen, rowsWritten, err
		}
		rowsWritten += written
	}
	return docsSeen, rowsWritten, nil
}

func snapshotRows(collectionName string, doc bson.M) []snapshotRow {
	locationID := normalizeLocation(doc["location"])
	date, ok := normalizeDate(doc["date"])
	if locationID == "" || !ok {
		return nil
	}

	data, ok := asMap(doc["data"])
	if !ok {
		return nil
	}
	items := asSlice(data["items"])
	if len(items) == 0 {
		return nil
	}

	rows := make([]snapshotRow, 0, len(items))
	for _, value := range items {
		item, ok := asMap(value)
		if !ok {
			continue
		}
		tag := normalizeString(item["tag"])
		if tag == "" {
			continue
		}
		rank, ok := normalizeRank(item["rank"])
		if !ok {
			continue
		}
		raw, err := json.Marshal(item)
		if err != nil {
			continue
		}
		rows = append(rows, snapshotRow{
			Kind:       collectionName,
			LocationID: locationID,
			Date:       date,
			Tag:        tag,
			Name:       normalizeString(item["name"]),
			Rank:       rank,
			Data:       string(raw),
		})
	}
	return rows
}

func flushRows(ctx context.Context, pool *pgxpool.Pool, rows map[string]snapshotRow, dryRun bool) (int64, error) {
	if len(rows) == 0 {
		return 0, nil
	}
	if dryRun {
		return int64(len(rows)), nil
	}
	if pool == nil {
		return 0, errors.New("Timescale pool is nil")
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `
		CREATE TEMP TABLE _ck_mongo_leaderboard_snapshot_items (
			kind text NOT NULL,
			location_id text NOT NULL,
			date date NOT NULL,
			tag text NOT NULL,
			name text NOT NULL,
			rank integer NOT NULL,
			data text NOT NULL
		) ON COMMIT DROP
	`); err != nil {
		return 0, err
	}

	copyRows := make([][]any, 0, len(rows))
	for _, row := range rows {
		copyRows = append(copyRows, []any{
			row.Kind,
			row.LocationID,
			row.Date,
			row.Tag,
			row.Name,
			row.Rank,
			row.Data,
		})
	}
	if _, err := tx.CopyFrom(
		ctx,
		pgx.Identifier{"_ck_mongo_leaderboard_snapshot_items"},
		[]string{"kind", "location_id", "date", "tag", "name", "rank", "data"},
		pgx.CopyFromRows(copyRows),
	); err != nil {
		return 0, err
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO leaderboard_snapshot_items (
			kind, location_id, date, tag, name, rank, data
		)
		SELECT kind, location_id, date, tag, name, rank, data::jsonb
		FROM _ck_mongo_leaderboard_snapshot_items
		ON CONFLICT (kind, location_id, date, tag) DO UPDATE SET
			name = EXCLUDED.name,
			rank = EXCLUDED.rank,
			data = EXCLUDED.data
		WHERE
			leaderboard_snapshot_items.name IS DISTINCT FROM EXCLUDED.name OR
			leaderboard_snapshot_items.rank IS DISTINCT FROM EXCLUDED.rank OR
			leaderboard_snapshot_items.data IS DISTINCT FROM EXCLUDED.data
	`); err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return int64(len(rows)), nil
}

func loadEnv(path string) (map[string]string, error) {
	values := map[string]string{}
	if path == "" {
		return values, nil
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") || !strings.Contains(line, "=") {
			continue
		}
		key, value, _ := strings.Cut(line, "=")
		key = strings.TrimSpace(key)
		value = strings.Trim(strings.TrimSpace(value), `"'`)
		values[key] = value
	}
	return values, scanner.Err()
}

func asMap(value any) (bson.M, bool) {
	switch typed := value.(type) {
	case bson.M:
		return typed, true
	case map[string]any:
		return bson.M(typed), true
	case bson.D:
		out := bson.M{}
		for _, elem := range typed {
			out[elem.Key] = elem.Value
		}
		return out, true
	default:
		return nil, false
	}
}

func asSlice(value any) []any {
	switch typed := value.(type) {
	case bson.A:
		return []any(typed)
	case []any:
		return typed
	default:
		return nil
	}
}

func normalizeLocation(value any) string {
	return strings.TrimSpace(fmt.Sprint(value))
}

func normalizeDate(value any) (time.Time, bool) {
	switch typed := value.(type) {
	case time.Time:
		return dayStart(typed), true
	case string:
		raw := strings.TrimSpace(typed)
		if len(raw) >= len("2006-01-02") {
			raw = raw[:len("2006-01-02")]
		}
		parsed, err := time.Parse("2006-01-02", raw)
		if err != nil {
			return time.Time{}, false
		}
		return dayStart(parsed), true
	default:
		return time.Time{}, false
	}
}

func normalizeString(value any) string {
	if value == nil {
		return ""
	}
	return fmt.Sprint(value)
}

func normalizeRank(value any) (int, bool) {
	var rank int64
	switch typed := value.(type) {
	case int:
		rank = int64(typed)
	case int32:
		rank = int64(typed)
	case int64:
		rank = typed
	case float64:
		rank = int64(typed)
	case string:
		parsed, err := strconv.ParseInt(typed, 10, 64)
		if err != nil {
			return 0, false
		}
		rank = parsed
	default:
		return 0, false
	}
	if rank <= 0 || rank > int64(^uint(0)>>1) {
		return 0, false
	}
	return int(rank), true
}

func dayStart(value time.Time) time.Time {
	year, month, day := value.UTC().Date()
	return time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
}

func rowKey(row snapshotRow) string {
	return row.Kind + "\x00" + row.LocationID + "\x00" + row.Date.Format("2006-01-02") + "\x00" + row.Tag
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
