-- +goose Up
ALTER TABLE public.server_logs
    ADD COLUMN disabled boolean DEFAULT false NOT NULL;

-- +goose Down
ALTER TABLE public.server_logs
    DROP COLUMN disabled;
