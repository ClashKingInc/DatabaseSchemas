-- +goose Up
-- +goose StatementBegin
CREATE FUNCTION pg_temp.ck_bool(value text, fallback boolean DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    IF value IS NULL OR btrim(value) = '' THEN RETURN fallback; END IF;
    RETURN value::boolean;
EXCEPTION WHEN OTHERS THEN RETURN fallback;
END
$$;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE FUNCTION pg_temp.ck_int(value text, fallback integer DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $$
BEGIN
    IF value IS NULL OR btrim(value) = '' THEN RETURN fallback; END IF;
    RETURN value::integer;
EXCEPTION WHEN OTHERS THEN RETURN fallback;
END
$$;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE FUNCTION pg_temp.ck_bigint(value text, fallback bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
    IF value IS NULL OR btrim(value) = '' THEN RETURN fallback; END IF;
    RETURN value::bigint;
EXCEPTION WHEN OTHERS THEN RETURN fallback;
END
$$;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE FUNCTION pg_temp.ck_float(value text, fallback double precision DEFAULT NULL)
RETURNS double precision LANGUAGE plpgsql AS $$
BEGIN
    IF value IS NULL OR btrim(value) = '' THEN RETURN fallback; END IF;
    RETURN value::double precision;
EXCEPTION WHEN OTHERS THEN RETURN fallback;
END
$$;
-- +goose StatementEnd

-- +goose StatementBegin
CREATE FUNCTION pg_temp.ck_role_mode(value jsonb, fallback text DEFAULT 'sync')
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    IF jsonb_typeof(value) <> 'array' THEN RETURN fallback; END IF;
    IF value @> '["Add"]'::jsonb AND value @> '["Remove"]'::jsonb THEN RETURN 'sync'; END IF;
    IF value @> '["Remove"]'::jsonb THEN RETURN 'remove'; END IF;
    IF value @> '["Add"]'::jsonb THEN RETURN 'add'; END IF;
    RETURN fallback;
END
$$;
-- +goose StatementEnd

CREATE TABLE public.server_settings (
    server_id text PRIMARY KEY REFERENCES public.servers(id) ON DELETE CASCADE,
    nickname_rule text,
    non_family_nickname_rule text,
    change_nickname boolean DEFAULT true NOT NULL,
    flair_non_family boolean DEFAULT true NOT NULL,
    auto_eval_nickname boolean DEFAULT false NOT NULL,
    autoeval_log_channel_id text,
    autoeval_enabled boolean DEFAULT false NOT NULL,
    full_whitelist_role_id text,
    autoboard_limit integer DEFAULT 0 NOT NULL,
    use_api_token boolean DEFAULT true NOT NULL,
    tied_stats_only boolean DEFAULT true NOT NULL,
    banlist_channel_id text,
    strike_log_channel_id text,
    reddit_feed_channel_id text,
    family_label text DEFAULT '' NOT NULL,
    greeting text,
    link_parse_clan boolean DEFAULT true NOT NULL,
    link_parse_army boolean DEFAULT true NOT NULL,
    link_parse_player boolean DEFAULT true NOT NULL,
    link_parse_base boolean DEFAULT true NOT NULL,
    link_parse_show boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.server_autoeval_triggers (
    server_id text NOT NULL REFERENCES public.servers(id) ON DELETE CASCADE,
    trigger text NOT NULL,
    position integer DEFAULT 0 NOT NULL,
    PRIMARY KEY (server_id, trigger)
);

CREATE TABLE public.server_blacklisted_roles (
    server_id text NOT NULL REFERENCES public.servers(id) ON DELETE CASCADE,
    role_id text NOT NULL,
    PRIMARY KEY (server_id, role_id)
);

CREATE TABLE public.server_link_parse_channels (
    server_id text NOT NULL REFERENCES public.servers(id) ON DELETE CASCADE,
    channel_id text NOT NULL,
    PRIMARY KEY (server_id, channel_id)
);

CREATE TABLE public.server_logs (
    server_id text NOT NULL REFERENCES public.servers(id) ON DELETE CASCADE,
    log_type text NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    channel_id text,
    thread_id text,
    webhook_id text,
    include_buttons boolean,
    ping_role_id text,
    PRIMARY KEY (server_id, log_type)
);

CREATE TABLE public.server_log_clans (
    server_id text NOT NULL,
    log_type text NOT NULL,
    clan_tag text NOT NULL,
    PRIMARY KEY (server_id, log_type, clan_tag),
    FOREIGN KEY (server_id, log_type) REFERENCES public.server_logs(server_id, log_type) ON DELETE CASCADE
);

CREATE TABLE public.server_welcome_panels (
    server_id text PRIMARY KEY REFERENCES public.servers(id) ON DELETE CASCADE,
    embed_name text,
    button_color text DEFAULT 'Grey' NOT NULL,
    welcome_channel_id text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.server_welcome_panel_buttons (
    server_id text NOT NULL REFERENCES public.server_welcome_panels(server_id) ON DELETE CASCADE,
    button_name text NOT NULL,
    position integer DEFAULT 0 NOT NULL,
    PRIMARY KEY (server_id, button_name)
);

CREATE TABLE public.role_rules (
    id uuid DEFAULT uuidv7() PRIMARY KEY,
    server_id text NOT NULL REFERENCES public.servers(id) ON DELETE CASCADE,
    clan_tag text,
    type text NOT NULL,
    option text NOT NULL,
    role_id text NOT NULL,
    mode text DEFAULT 'sync' NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT role_rules_type_check CHECK (type = ANY (ARRAY[
        'townhall', 'builderhall', 'league', 'builder_league',
        'clan_role', 'clan_category', 'family', 'achievement',
        'status', 'ignored'
    ])),
    CONSTRAINT role_rules_mode_check CHECK (mode = ANY (ARRAY['add', 'remove', 'sync'])),
    CONSTRAINT role_rules_scope_check CHECK (clan_tag IS NULL OR type = 'clan_role'),
    CONSTRAINT role_rules_option_check CHECK (btrim(option) <> ''),
    CONSTRAINT role_rules_role_id_check CHECK (btrim(role_id) <> ''),
    CONSTRAINT role_rules_clan_fkey FOREIGN KEY (clan_tag, server_id)
        REFERENCES public.server_clans(tag, server_id) ON DELETE CASCADE,
    UNIQUE NULLS NOT DISTINCT (server_id, clan_tag, type, option, role_id)
);

CREATE INDEX idx_role_rules_server_type ON public.role_rules (server_id, type);
CREATE INDEX idx_role_rules_clan ON public.role_rules (server_id, clan_tag) WHERE clan_tag IS NOT NULL;

CREATE TABLE public.server_clan_settings (
    server_id text NOT NULL,
    clan_tag text NOT NULL,
    greeting text DEFAULT '' NOT NULL,
    auto_greet_option text DEFAULT 'Never' NOT NULL,
    ban_alert_channel_id text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    PRIMARY KEY (server_id, clan_tag),
    FOREIGN KEY (clan_tag, server_id) REFERENCES public.server_clans(tag, server_id) ON DELETE CASCADE
);

CREATE TABLE public.countdowns (
    server_id text NOT NULL REFERENCES public.servers(id) ON DELETE CASCADE,
    clan_tag text,
    channel_id text NOT NULL,
    type text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT countdowns_type_check CHECK (type = ANY (ARRAY[
        'clan_games_timer', 'cwl_timer', 'raid_weekend_timer',
        'season_end_timer', 'season_day_timer', 'war_score', 'war_timer'
    ])),
    CONSTRAINT countdowns_scope_check CHECK (
        (type = ANY (ARRAY['war_score', 'war_timer']) AND clan_tag IS NOT NULL)
        OR
        (type <> ALL (ARRAY['war_score', 'war_timer']) AND clan_tag IS NULL)
    ),
    CONSTRAINT countdowns_clan_fkey FOREIGN KEY (clan_tag, server_id)
        REFERENCES public.server_clans(tag, server_id) ON DELETE CASCADE,
    UNIQUE NULLS NOT DISTINCT (server_id, clan_tag, type)
);

CREATE INDEX idx_countdowns_server ON public.countdowns (server_id, type);

ALTER TABLE public.clan_logs
    ADD COLUMN IF NOT EXISTS channel_id text,
    ADD COLUMN IF NOT EXISTS active_war_id text,
    ADD COLUMN IF NOT EXISTS active_raid_id text,
    ADD COLUMN IF NOT EXISTS message_id text;

INSERT INTO public.server_settings (
    server_id, nickname_rule, non_family_nickname_rule, change_nickname,
    flair_non_family, auto_eval_nickname, autoeval_log_channel_id,
    autoeval_enabled, full_whitelist_role_id,
    autoboard_limit, use_api_token, tied_stats_only, banlist_channel_id,
    strike_log_channel_id, reddit_feed_channel_id, family_label, greeting,
    link_parse_clan, link_parse_army, link_parse_player, link_parse_base,
    link_parse_show, updated_at
)
SELECT id,
       NULLIF(data->>'nickname_rule', ''),
       NULLIF(data->>'non_family_nickname_rule', ''),
       pg_temp.ck_bool(data->>'change_nickname', true),
       pg_temp.ck_bool(data->>'flair_non_family', true),
       pg_temp.ck_bool(data->>'auto_eval_nickname', false),
       NULLIF(data->>'autoeval_log', ''),
       pg_temp.ck_bool(data->>'autoeval', false),
       NULLIF(data->>'full_whitelist_role', ''),
       pg_temp.ck_int(data->>'autoboard_limit', 0),
       pg_temp.ck_bool(data->>'api_token', true),
       pg_temp.ck_bool(data->>'tied', true),
       NULLIF(data->>'banlist', ''),
       NULLIF(data->>'strike_log', ''),
       NULLIF(data->>'reddit_feed', ''),
       COALESCE(data->>'family_label', ''),
       NULLIF(data->>'greeting', ''),
       pg_temp.ck_bool(data#>>'{link_parse,clan}', true),
       pg_temp.ck_bool(data#>>'{link_parse,army}', true),
       pg_temp.ck_bool(data#>>'{link_parse,player}', true),
       pg_temp.ck_bool(data#>>'{link_parse,base}', true),
       pg_temp.ck_bool(data#>>'{link_parse,show}', true),
       updated_at
FROM public.servers
ON CONFLICT (server_id) DO NOTHING;

INSERT INTO public.server_autoeval_triggers (server_id, trigger, position)
SELECT s.id, value, ordinality::integer
FROM public.servers s
CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(s.data->'autoeval_triggers') = 'array' THEN s.data->'autoeval_triggers' ELSE '[]'::jsonb END
) WITH ORDINALITY AS item(value, ordinality)
ON CONFLICT DO NOTHING;

INSERT INTO public.server_blacklisted_roles (server_id, role_id)
SELECT s.id, value
FROM public.servers s
CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(s.data->'blacklisted_roles') = 'array' THEN s.data->'blacklisted_roles' ELSE '[]'::jsonb END
) AS item(value)
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, type, option, role_id, mode)
SELECT s.id, 'clan_category', item.key, item.value #>> '{}', pg_temp.ck_role_mode(s.data->'role_treatment')
FROM public.servers s
CROSS JOIN LATERAL jsonb_each(
    CASE WHEN jsonb_typeof(s.data->'category_roles') = 'object' THEN s.data->'category_roles' ELSE '{}'::jsonb END
) AS item(key, value)
WHERE item.value #>> '{}' <> ''
ON CONFLICT DO NOTHING;

INSERT INTO public.server_link_parse_channels (server_id, channel_id)
SELECT s.id, value
FROM public.servers s
CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(s.data#>'{link_parse,channels}') = 'array' THEN s.data#>'{link_parse,channels}' ELSE '[]'::jsonb END
) AS item(value)
ON CONFLICT DO NOTHING;

INSERT INTO public.server_logs (server_id, log_type, enabled, channel_id, thread_id, webhook_id, include_buttons, ping_role_id)
SELECT s.id, item.key,
       pg_temp.ck_bool(item.value->>'enabled', item.value ? 'webhook'),
       NULLIF(item.value->>'channel', ''), NULLIF(item.value->>'thread', ''),
       NULLIF(item.value->>'webhook', ''),
       pg_temp.ck_bool(item.value->>'include_buttons'),
       NULLIF(item.value->>'ping_role', '')
FROM public.servers s
CROSS JOIN LATERAL jsonb_each(
    CASE WHEN jsonb_typeof(s.logs_config) = 'object' THEN s.logs_config ELSE '{}'::jsonb END
) AS item(key, value)
WHERE jsonb_typeof(item.value) = 'object' AND item.key <> 'welcome_link'
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, type, option, role_id, mode)
SELECT s.id, 'status',
       COALESCE(NULLIF(item.value->>'key', ''), NULLIF(item.value->>'number', ''), NULLIF(item.value->>'months', ''), 'member'),
       COALESCE(NULLIF(item.value->>'id', ''), NULLIF(item.value->>'role', '')),
       pg_temp.ck_role_mode(s.data->'role_treatment')
FROM public.servers s
CROSS JOIN LATERAL jsonb_array_elements(
    CASE WHEN jsonb_typeof(s.status_roles->'discord') = 'array' THEN s.status_roles->'discord' ELSE '[]'::jsonb END
) WITH ORDINALITY AS item(value, ordinality)
WHERE COALESCE(NULLIF(item.value->>'id', ''), NULLIF(item.value->>'role', '')) IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.server_welcome_panels (server_id, embed_name, button_color, welcome_channel_id, updated_at)
SELECT s.id,
       COALESCE(NULLIF(s.logs_config#>>'{welcome_link,embed_name}', ''), NULLIF(s.data->>'welcome_link_embed', '')),
       COALESCE(NULLIF(s.logs_config#>>'{welcome_link,button_color}', ''), 'Grey'),
       COALESCE(NULLIF(s.logs_config#>>'{welcome_link,welcome_channel}', ''), NULLIF(s.data->>'welcome_link_channel', '')),
       s.updated_at
FROM public.servers s
WHERE s.logs_config ? 'welcome_link' OR s.data ? 'welcome_link_embed' OR s.data ? 'welcome_link_channel'
ON CONFLICT (server_id) DO NOTHING;

INSERT INTO public.server_welcome_panel_buttons (server_id, button_name, position)
SELECT s.id, item.value, item.ordinality::integer
FROM public.servers s
CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(s.logs_config#>'{welcome_link,buttons}') = 'array'
         THEN s.logs_config#>'{welcome_link,buttons}' ELSE '[]'::jsonb END
) WITH ORDINALITY AS item(value, ordinality)
ON CONFLICT DO NOTHING;

INSERT INTO public.countdowns (server_id, clan_tag, type, channel_id)
SELECT s.id, NULL,
       CASE item.key
           WHEN 'gamesCountdown' THEN 'clan_games_timer'
           WHEN 'cwlCountdown' THEN 'cwl_timer'
           WHEN 'raidCountdown' THEN 'raid_weekend_timer'
           WHEN 'eosCountdown' THEN 'season_end_timer'
           WHEN 'seasonCountdown' THEN 'season_day_timer'
       END,
       item.value
FROM public.servers s
CROSS JOIN LATERAL jsonb_each_text(
    CASE WHEN jsonb_typeof(s.countdowns) = 'object' THEN s.countdowns ELSE '{}'::jsonb END
) AS item(key, value)
WHERE item.value <> '' AND item.key = ANY (ARRAY[
    'gamesCountdown', 'cwlCountdown', 'raidCountdown', 'eosCountdown', 'seasonCountdown'
])
ON CONFLICT DO NOTHING;

INSERT INTO public.clan_categories (server_id, name)
SELECT DISTINCT server_id, data->>'category'
FROM public.server_clans
WHERE COALESCE(data->>'category', '') <> ''
ON CONFLICT (server_id, name) DO NOTHING;

UPDATE public.server_clans sc
SET category_id = category.id
FROM public.clan_categories category
WHERE sc.server_id = category.server_id
  AND sc.data->>'category' = category.name
  AND sc.category_id IS NULL;

INSERT INTO public.server_clan_settings (
    server_id, clan_tag, greeting, auto_greet_option,
    ban_alert_channel_id, updated_at
)
SELECT server_id, tag, COALESCE(data->>'greeting', ''),
       COALESCE(NULLIF(data->>'auto_greet_option', ''), 'Never'),
       NULLIF(data->>'ban_alert_channel', ''),
       updated_at
FROM public.server_clans
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, clan_tag, type, option, role_id, mode)
SELECT server_id, tag, 'clan_role', 'member', data->>'generalRole', 'sync'
FROM public.server_clans
WHERE COALESCE(data->>'generalRole', '') <> ''
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, clan_tag, type, option, role_id, mode)
SELECT server_id, tag, 'clan_role', 'leader', data->>'leaderRole',
       CASE WHEN pg_temp.ck_bool(data->>'leadership_eval', true) THEN 'sync' ELSE 'remove' END
FROM public.server_clans
WHERE COALESCE(data->>'leaderRole', '') <> ''
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, type, option, role_id, mode)
SELECT settings.server_id, 'family', 'member', role.value #>> '{}',
       pg_temp.ck_role_mode(settings.data->'role_treatment')
FROM public.server_role_settings settings
CROSS JOIN LATERAL jsonb_path_query(settings.family_roles, '$.** ? (@.type() == "string")') AS role(value)
WHERE COALESCE(role.value #>> '{}', '') <> ''
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, type, option, role_id, mode)
SELECT settings.server_id, 'family', 'not_family', role.value #>> '{}',
       pg_temp.ck_role_mode(settings.data->'role_treatment')
FROM public.server_role_settings settings
CROSS JOIN LATERAL jsonb_path_query(settings.not_family_roles, '$.** ? (@.type() == "string")') AS role(value)
WHERE COALESCE(role.value #>> '{}', '') <> ''
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, type, option, role_id, mode)
SELECT settings.server_id, 'family', 'only_family', role.value #>> '{}',
       pg_temp.ck_role_mode(settings.data->'role_treatment')
FROM public.server_role_settings settings
CROSS JOIN LATERAL jsonb_path_query(settings.family_exclusive_roles, '$.** ? (@.type() == "string")') AS role(value)
WHERE COALESCE(role.value #>> '{}', '') <> ''
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, type, option, role_id, mode)
SELECT settings.server_id, 'ignored', 'evaluation', role.value #>> '{}', 'sync'
FROM public.server_role_settings settings
CROSS JOIN LATERAL jsonb_path_query(settings.ignored_roles, '$.** ? (@.type() == "string")') AS role(value)
WHERE COALESCE(role.value #>> '{}', '') <> ''
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, type, option, role_id, mode, created_at, updated_at)
SELECT binding.server_id,
       CASE binding.role_type
           WHEN 'family_position' THEN 'clan_role'
           WHEN 'family' THEN 'family'
           WHEN 'not_family' THEN 'family'
           WHEN 'only_family' THEN 'family'
           WHEN 'ignored' THEN 'ignored'
           ELSE binding.role_type
       END,
       CASE
           WHEN binding.role_type = 'family_position' THEN
               CASE binding.role_key
                   WHEN 'family_member_roles' THEN 'member'
                   WHEN 'family_elder_roles' THEN 'elder'
                   WHEN 'family_co-leader_roles' THEN 'co_leader'
                   WHEN 'family_leader_roles' THEN 'leader'
                   ELSE binding.role_key
               END
           WHEN binding.role_type = 'family' THEN 'member'
           WHEN binding.role_type = 'not_family' THEN 'not_family'
           WHEN binding.role_type = 'only_family' THEN 'only_family'
           WHEN binding.role_type = 'ignored' THEN 'evaluation'
           ELSE binding.role_key
       END,
       binding.role_id,
       pg_temp.ck_role_mode(server.data->'role_treatment'),
       binding.created_at,
       binding.updated_at
FROM public.role_bindings binding
JOIN public.servers server ON server.id = binding.server_id
WHERE binding.role_type = ANY (ARRAY[
    'townhall', 'builderhall', 'league', 'builder_league',
    'achievement', 'family_position', 'family', 'not_family',
    'only_family', 'ignored'
])
  AND (
      COALESCE(binding.role_key, '') <> ''
      OR binding.role_type = ANY (ARRAY['family', 'not_family', 'only_family', 'ignored'])
  )
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, clan_tag, type, option, role_id, mode, created_at, updated_at)
SELECT role.server_id, role.clan_tag, 'clan_role',
       CASE role.position WHEN 'coleader' THEN 'co_leader' ELSE role.position END,
       role.role_id, pg_temp.ck_role_mode(server.data->'role_treatment'), now(), now()
FROM public.clan_position_roles role
JOIN public.servers server ON server.id = role.server_id
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, type, option, role_id, mode)
SELECT role.server_id,
       CASE WHEN role.is_townhall THEN 'townhall' ELSE 'builderhall' END,
       role.hall_level::text, role.role_id,
       pg_temp.ck_role_mode(server.data->'role_treatment')
FROM public.hall_roles role
JOIN public.servers server ON server.id = role.server_id
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, type, option, role_id, mode)
SELECT role.server_id, 'league', role.league_id::text, role.role_id,
       pg_temp.ck_role_mode(server.data->'role_treatment')
FROM public.league_roles role
JOIN public.servers server ON server.id = role.server_id
ON CONFLICT DO NOTHING;

INSERT INTO public.role_rules (server_id, type, option, role_id, mode, created_at)
SELECT role.server_id, 'ignored', 'evaluation', role.role_id, 'sync', role.created_at
FROM public.role_ignore_bindings role
ON CONFLICT DO NOTHING;

INSERT INTO public.clan_logs (
    server_id, clan_tag, type, webhook_token, thread_id, channel_id,
    active_war_id, active_raid_id, message_id
)
SELECT sc.server_id, sc.tag, item.key, item.value->>'webhook',
       NULLIF(item.value->>'thread', ''), NULLIF(item.value->>'channel', ''),
       NULLIF(item.value->>'war_id', ''), NULLIF(item.value->>'raid_id', ''),
       COALESCE(NULLIF(item.value->>'war_message', ''), NULLIF(item.value->>'raid_message', ''))
FROM public.server_clans sc
CROSS JOIN LATERAL jsonb_each(
    CASE WHEN jsonb_typeof(sc.logs_config) = 'object' THEN sc.logs_config ELSE '{}'::jsonb END
) AS item(key, value)
WHERE jsonb_typeof(item.value) = 'object' AND COALESCE(item.value->>'webhook', '') <> ''
ON CONFLICT (server_id, clan_tag, type) DO UPDATE SET
    webhook_token = EXCLUDED.webhook_token,
    thread_id = EXCLUDED.thread_id,
    channel_id = EXCLUDED.channel_id,
    active_war_id = EXCLUDED.active_war_id,
    active_raid_id = EXCLUDED.active_raid_id,
    message_id = EXCLUDED.message_id;

INSERT INTO public.countdowns (server_id, clan_tag, type, channel_id)
SELECT sc.server_id, sc.tag,
       CASE item.key WHEN 'warCountdown' THEN 'war_score' WHEN 'warTimerCountdown' THEN 'war_timer' END,
       item.value
FROM public.server_clans sc
CROSS JOIN LATERAL jsonb_each_text(
    CASE WHEN jsonb_typeof(sc.countdowns) = 'object' THEN sc.countdowns ELSE '{}'::jsonb END
) AS item(key, value)
WHERE item.value <> '' AND item.key = ANY (ARRAY['warCountdown', 'warTimerCountdown'])
ON CONFLICT DO NOTHING;

ALTER TABLE public.rosters
    ADD COLUMN IF NOT EXISTS description text,
    ADD COLUMN IF NOT EXISTS roster_type text DEFAULT 'clan' NOT NULL,
    ADD COLUMN IF NOT EXISTS signup_scope text DEFAULT 'clan-only' NOT NULL,
    ADD COLUMN IF NOT EXISTS min_townhall integer,
    ADD COLUMN IF NOT EXISTS max_townhall integer,
    ADD COLUMN IF NOT EXISTS roster_size integer,
    ADD COLUMN IF NOT EXISTS min_signups integer,
    ADD COLUMN IF NOT EXISTS max_accounts_per_user integer,
    ADD COLUMN IF NOT EXISTS townhall_restriction text,
    ADD COLUMN IF NOT EXISTS default_signup_category text,
    ADD COLUMN IF NOT EXISTS image_url text,
    ADD COLUMN IF NOT EXISTS event_start_time bigint,
    ADD COLUMN IF NOT EXISTS recurrence_days integer,
    ADD COLUMN IF NOT EXISTS recurrence_day_of_month integer;

UPDATE public.rosters
SET description = COALESCE(NULLIF(data->>'description', ''), description),
    alias = COALESCE(NULLIF(alias, ''), custom_id, id::text),
    roster_type = COALESCE(NULLIF(data->>'roster_type', ''), roster_type),
    signup_scope = COALESCE(NULLIF(data->>'signup_scope', ''), signup_scope),
    min_townhall = pg_temp.ck_int(data->>'min_th'),
    max_townhall = pg_temp.ck_int(data->>'max_th'),
    roster_size = pg_temp.ck_int(data->>'roster_size'),
    min_signups = pg_temp.ck_int(data->>'min_signups'),
    max_accounts_per_user = pg_temp.ck_int(data->>'max_accounts_per_user'),
    townhall_restriction = NULLIF(data->>'th_restriction', ''),
    default_signup_category = NULLIF(data->>'default_signup_category', ''),
    image_url = COALESCE(NULLIF(data->>'image', ''), image_url),
    event_start_time = pg_temp.ck_bigint(data->>'event_start_time'),
    recurrence_days = pg_temp.ck_int(data->>'recurrence_days'),
    recurrence_day_of_month = pg_temp.ck_int(data->>'recurrence_day_of_month');

ALTER TABLE public.rosters
    ALTER COLUMN description DROP NOT NULL,
    DROP COLUMN IF EXISTS linked_clan_tag,
    DROP COLUMN IF EXISTS title,
    DROP COLUMN IF EXISTS max_size,
    DROP COLUMN IF EXISTS minimum_townhall,
    DROP COLUMN IF EXISTS maximum_townhall,
    DROP COLUMN IF EXISTS signup_role_id;

ALTER TABLE public.roster_members
    DROP COLUMN IF EXISTS roster_group_id,
    ADD COLUMN IF NOT EXISTS name text DEFAULT '' NOT NULL,
    ADD COLUMN IF NOT EXISTS townhall integer DEFAULT 0 NOT NULL,
    ADD COLUMN IF NOT EXISTS hero_levels integer,
    ADD COLUMN IF NOT EXISTS discord_user_id text,
    ADD COLUMN IF NOT EXISTS discord_username text,
    ADD COLUMN IF NOT EXISTS discord_avatar_url text,
    ADD COLUMN IF NOT EXISTS current_clan_name text,
    ADD COLUMN IF NOT EXISTS current_clan_tag text,
    ADD COLUMN IF NOT EXISTS war_preference boolean,
    ADD COLUMN IF NOT EXISTS trophies integer,
    ADD COLUMN IF NOT EXISTS substitute boolean,
    ADD COLUMN IF NOT EXISTS signup_group text,
    ADD COLUMN IF NOT EXISTS hitrate double precision,
    ADD COLUMN IF NOT EXISTS last_online bigint,
    ADD COLUMN IF NOT EXISTS current_league text,
    ADD COLUMN IF NOT EXISTS added_at bigint,
    ADD COLUMN IF NOT EXISTS last_updated bigint,
    ADD COLUMN IF NOT EXISTS is_in_family boolean,
    ADD COLUMN IF NOT EXISTS member_status text,
    ADD COLUMN IF NOT EXISTS error_details text,
    ADD COLUMN IF NOT EXISTS position integer DEFAULT 0 NOT NULL;

INSERT INTO public.roster_members (
    roster_id, tag, name, townhall, hero_levels, discord_user_id,
    discord_username, discord_avatar_url, current_clan_name,
    current_clan_tag, war_preference, trophies, substitute, signup_group,
    hitrate, last_online, current_league, added_at, last_updated,
    is_in_family, member_status, error_details, position
)
SELECT r.id, member.value->>'tag', COALESCE(member.value->>'name', ''),
       pg_temp.ck_int(member.value->>'townhall', 0),
       pg_temp.ck_int(member.value->>'hero_lvs'),
       NULLIF(member.value->>'discord', ''), NULLIF(member.value->>'discord_username', ''),
       NULLIF(member.value->>'discord_avatar_url', ''), NULLIF(member.value->>'current_clan', ''),
       NULLIF(member.value->>'current_clan_tag', ''),
       pg_temp.ck_bool(member.value->>'war_pref'),
       pg_temp.ck_int(member.value->>'trophies'),
       pg_temp.ck_bool(member.value->>'sub'),
       NULLIF(member.value->>'signup_group', ''), pg_temp.ck_float(member.value->>'hitrate'),
       pg_temp.ck_bigint(member.value->>'last_online'), NULLIF(member.value->>'current_league', ''),
       pg_temp.ck_bigint(member.value->>'added_at'), pg_temp.ck_bigint(member.value->>'last_updated'),
       pg_temp.ck_bool(member.value->>'is_in_family'),
       NULLIF(member.value->>'member_status', ''), NULLIF(member.value->>'error_details', ''),
       member.ordinality::integer
FROM public.rosters r
CROSS JOIN LATERAL jsonb_array_elements(
    CASE WHEN jsonb_typeof(r.members) = 'array' THEN r.members ELSE '[]'::jsonb END
) WITH ORDINALITY AS member(value, ordinality)
WHERE COALESCE(member.value->>'tag', '') <> ''
ON CONFLICT (tag, roster_id) DO UPDATE SET
    name = EXCLUDED.name, townhall = EXCLUDED.townhall,
    hero_levels = EXCLUDED.hero_levels, discord_user_id = EXCLUDED.discord_user_id,
    discord_username = EXCLUDED.discord_username, discord_avatar_url = EXCLUDED.discord_avatar_url,
    current_clan_name = EXCLUDED.current_clan_name, current_clan_tag = EXCLUDED.current_clan_tag,
    war_preference = EXCLUDED.war_preference, trophies = EXCLUDED.trophies,
    substitute = EXCLUDED.substitute, signup_group = EXCLUDED.signup_group,
    hitrate = EXCLUDED.hitrate, last_online = EXCLUDED.last_online,
    current_league = EXCLUDED.current_league, added_at = EXCLUDED.added_at,
    last_updated = EXCLUDED.last_updated, is_in_family = EXCLUDED.is_in_family,
    member_status = EXCLUDED.member_status, error_details = EXCLUDED.error_details,
    position = EXCLUDED.position;

CREATE TABLE public.roster_allowed_signup_categories (
    roster_id uuid NOT NULL REFERENCES public.rosters(id) ON DELETE CASCADE,
    category_id text NOT NULL,
    position integer DEFAULT 0 NOT NULL,
    PRIMARY KEY (roster_id, category_id)
);

CREATE TABLE public.roster_display_columns (
    roster_id uuid NOT NULL REFERENCES public.rosters(id) ON DELETE CASCADE,
    column_name text NOT NULL,
    position integer DEFAULT 0 NOT NULL,
    PRIMARY KEY (roster_id, column_name)
);

CREATE TABLE public.roster_sort_fields (
    roster_id uuid NOT NULL REFERENCES public.rosters(id) ON DELETE CASCADE,
    field_name text NOT NULL,
    position integer DEFAULT 0 NOT NULL,
    PRIMARY KEY (roster_id, field_name)
);

INSERT INTO public.roster_allowed_signup_categories (roster_id, category_id, position)
SELECT r.id, item.value, item.ordinality::integer
FROM public.rosters r
CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(r.data->'allowed_signup_categories') = 'array' THEN r.data->'allowed_signup_categories' ELSE '[]'::jsonb END
) WITH ORDINALITY AS item(value, ordinality)
ON CONFLICT DO NOTHING;

INSERT INTO public.roster_display_columns (roster_id, column_name, position)
SELECT r.id, item.value, item.ordinality::integer
FROM public.rosters r
CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(r.data->'columns') = 'array' THEN r.data->'columns' ELSE '[]'::jsonb END
) WITH ORDINALITY AS item(value, ordinality)
ON CONFLICT DO NOTHING;

INSERT INTO public.roster_sort_fields (roster_id, field_name, position)
SELECT r.id, item.value, item.ordinality::integer
FROM public.rosters r
CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(r.data->'sort') = 'array' THEN r.data->'sort' ELSE '[]'::jsonb END
) WITH ORDINALITY AS item(value, ordinality)
ON CONFLICT DO NOTHING;

ALTER TABLE public.roster_groups
    ADD COLUMN IF NOT EXISTS alias text,
    ADD COLUMN IF NOT EXISTS max_accounts_per_user integer,
    ADD COLUMN IF NOT EXISTS roster_size integer,
    ADD COLUMN IF NOT EXISTS min_signups integer,
    ADD COLUMN IF NOT EXISTS default_signup_category text;

UPDATE public.roster_groups
SET alias = COALESCE(NULLIF(data->>'alias', ''), NULLIF(name, '')),
    max_accounts_per_user = pg_temp.ck_int(data->>'max_accounts_per_user'),
    roster_size = pg_temp.ck_int(data->>'roster_size'),
    min_signups = pg_temp.ck_int(data->>'min_signups'),
    default_signup_category = NULLIF(data->>'default_signup_category', '');

CREATE TABLE public.roster_group_allowed_signup_categories (
    group_id text NOT NULL REFERENCES public.roster_groups(group_id) ON DELETE CASCADE,
    category_id text NOT NULL,
    position integer DEFAULT 0 NOT NULL,
    PRIMARY KEY (group_id, category_id)
);

INSERT INTO public.roster_group_allowed_signup_categories (group_id, category_id, position)
SELECT groups.group_id, item.value, item.ordinality::integer
FROM public.roster_groups groups
CROSS JOIN LATERAL jsonb_array_elements_text(
    CASE WHEN jsonb_typeof(groups.data->'allowed_signup_categories') = 'array'
         THEN groups.data->'allowed_signup_categories' ELSE '[]'::jsonb END
) WITH ORDINALITY AS item(value, ordinality)
WHERE groups.group_id IS NOT NULL
ON CONFLICT DO NOTHING;

ALTER TABLE public.roster_signup_categories
    ADD COLUMN IF NOT EXISTS alias text;

UPDATE public.roster_signup_categories
SET alias = COALESCE(NULLIF(data->>'alias', ''), NULLIF(name, ''));

ALTER TABLE public.roster_automation_rules
    ADD COLUMN IF NOT EXISTS roster_id text,
    ADD COLUMN IF NOT EXISTS action_type text DEFAULT '' NOT NULL,
    ADD COLUMN IF NOT EXISTS offset_seconds integer DEFAULT 0 NOT NULL,
    ADD COLUMN IF NOT EXISTS discord_channel_id text,
    ADD COLUMN IF NOT EXISTS ping_type text,
    ADD COLUMN IF NOT EXISTS executed boolean DEFAULT false NOT NULL,
    ADD COLUMN IF NOT EXISTS executed_at bigint,
    ADD COLUMN IF NOT EXISTS last_triggered_at bigint,
    ADD COLUMN IF NOT EXISTS execution_status text,
    ADD COLUMN IF NOT EXISTS last_missed_at bigint;

UPDATE public.roster_automation_rules
SET roster_id = NULLIF(data->>'roster_id', ''),
    action_type = COALESCE(NULLIF(data->>'action_type', ''), action_type),
    offset_seconds = pg_temp.ck_int(data->>'offset_seconds', 0),
    discord_channel_id = NULLIF(data->>'discord_channel_id', ''),
    ping_type = NULLIF(data#>>'{options,ping_type}', ''),
    executed = pg_temp.ck_bool(data->>'executed', false),
    executed_at = pg_temp.ck_bigint(data->>'executed_at'),
    last_triggered_at = pg_temp.ck_bigint(data->>'last_triggered_at'),
    execution_status = NULLIF(data->>'execution_status', ''),
    last_missed_at = pg_temp.ck_bigint(data->>'last_missed_at');

ALTER TABLE public.roster_groups DROP COLUMN data;
ALTER TABLE public.roster_signup_categories DROP COLUMN data;
ALTER TABLE public.roster_automation_rules DROP COLUMN data;

DROP TABLE public.bot_sync_status;

DROP TABLE public.clan_position_roles;
DROP TABLE public.hall_roles;
DROP TABLE public.league_roles;
DROP TABLE public.role_ignore_bindings;
DROP TABLE public.role_bindings;
DROP TABLE public.server_role_settings;
DROP TABLE public.search_groups;

ALTER TABLE public.servers
    DROP COLUMN logs_config,
    DROP COLUMN status_roles,
    DROP COLUMN countdowns,
    DROP COLUMN data;

ALTER TABLE public.server_clans
    DROP COLUMN logs_config,
    DROP COLUMN countdowns,
    DROP COLUMN data;

ALTER TABLE public.rosters
    DROP COLUMN members,
    DROP COLUMN data;

-- +goose Down
DO $$
BEGIN
    RAISE EXCEPTION '019 is an irreversible data-preserving cutover; restore from a verified backup instead of migrating down';
END
$$;
