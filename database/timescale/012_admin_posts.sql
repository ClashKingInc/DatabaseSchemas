-- +goose Up
CREATE TABLE IF NOT EXISTS public.admin_posts (
    id uuid DEFAULT uuidv7() NOT NULL PRIMARY KEY,
    slug text NOT NULL UNIQUE,
    title text NOT NULL,
    summary text NOT NULL,
    hero_image_url text,
    body_blocks jsonb DEFAULT '[]'::jsonb NOT NULL,
    target_route text,
    platforms text[] DEFAULT '{ios,android,web}'::text[] NOT NULL,
    dismissible boolean DEFAULT true NOT NULL,
    priority integer DEFAULT 10 NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    also_push_on_publish boolean DEFAULT false NOT NULL,
    push_title text,
    push_body text,
    published_at timestamp with time zone,
    push_sent_at timestamp with time zone,
    created_by text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT admin_posts_status_check
        CHECK ((status = ANY (ARRAY['draft'::text, 'scheduled'::text, 'live'::text, 'expired'::text, 'archived'::text])))
);

CREATE INDEX IF NOT EXISTS idx_admin_posts_status ON public.admin_posts (status);
CREATE INDEX IF NOT EXISTS idx_admin_posts_starts_at ON public.admin_posts (starts_at) WHERE status = 'scheduled';

-- +goose Down
DROP TABLE IF EXISTS public.admin_posts CASCADE;
