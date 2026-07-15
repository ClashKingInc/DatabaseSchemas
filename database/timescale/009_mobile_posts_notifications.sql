-- +goose Up
ALTER TABLE public.mobile_push_devices
    ADD COLUMN IF NOT EXISTS authorization_status text DEFAULT 'not_determined'::text NOT NULL,
    ADD COLUMN IF NOT EXISTS locale text DEFAULT ''::text NOT NULL,
    ADD COLUMN IF NOT EXISTS timezone text DEFAULT ''::text NOT NULL;

-- +goose StatementBegin
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'mobile_push_devices_authorization_status_check'
    ) THEN
        ALTER TABLE public.mobile_push_devices
            ADD CONSTRAINT mobile_push_devices_authorization_status_check
            CHECK (authorization_status = ANY (ARRAY[
                'authorized'::text,
                'provisional'::text,
                'denied'::text,
                'not_determined'::text
            ]));
    END IF;
END $$;
-- +goose StatementEnd

CREATE TABLE IF NOT EXISTS public.mobile_notification_preferences (
    user_id text NOT NULL,
    device_id text NOT NULL,
    environment text DEFAULT 'production'::text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    locale text DEFAULT ''::text NOT NULL,
    timezone text DEFAULT ''::text NOT NULL,
    enabled_types text[] DEFAULT '{}'::text[] NOT NULL,
    war_attack_modes text[] DEFAULT '{}'::text[] NOT NULL,
    event_types text[] DEFAULT '{}'::text[] NOT NULL,
    reminder_timings text[] DEFAULT '{}'::text[] NOT NULL,
    account_scope text DEFAULT 'all'::text NOT NULL,
    selected_accounts text[] DEFAULT '{}'::text[] NOT NULL,
    selected_town_halls integer[] DEFAULT '{}'::integer[] NOT NULL,
    selected_clan_tags text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    PRIMARY KEY (user_id, device_id, environment),
    CONSTRAINT mobile_notification_preferences_environment_check
        CHECK (environment = ANY (ARRAY['sandbox'::text, 'production'::text])),
    CONSTRAINT mobile_notification_preferences_account_scope_check
        CHECK (account_scope = ANY (ARRAY['all'::text, 'selected'::text]))
);

CREATE TABLE IF NOT EXISTS public.mobile_notification_subscriptions (
    id uuid DEFAULT uuidv7() NOT NULL PRIMARY KEY,
    user_id text NOT NULL,
    device_id text NOT NULL,
    environment text DEFAULT 'production'::text NOT NULL,
    notification_type text NOT NULL,
    player_tag text DEFAULT ''::text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT mobile_notification_subscriptions_environment_check
        CHECK (environment = ANY (ARRAY['sandbox'::text, 'production'::text]))
);

CREATE INDEX IF NOT EXISTS idx_mobile_notification_preferences_delivery
    ON public.mobile_notification_preferences (environment, enabled)
    WHERE enabled = true;

CREATE INDEX IF NOT EXISTS idx_mobile_notification_subscriptions_device
    ON public.mobile_notification_subscriptions (user_id, device_id, environment);

CREATE TABLE IF NOT EXISTS public.admin_posts (
    id uuid DEFAULT uuidv7() NOT NULL PRIMARY KEY,
    slug text NOT NULL UNIQUE,
    title text NOT NULL,
    summary text NOT NULL,
    hero_image_url text,
    body_blocks jsonb DEFAULT '[]'::jsonb NOT NULL,
    presentation_type text DEFAULT 'article'::text NOT NULL,
    story_url text,
    story_version integer DEFAULT 1 NOT NULL,
    story_history text[] DEFAULT '{}'::text[] NOT NULL,
    revision_number integer DEFAULT 1 NOT NULL,
    show_on_home boolean DEFAULT true NOT NULL,
    pinned_on_home boolean DEFAULT false NOT NULL,
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
        CHECK ((status = ANY (ARRAY['draft'::text, 'scheduled'::text, 'live'::text, 'expired'::text, 'archived'::text]))),
    CONSTRAINT admin_posts_presentation_type_check
        CHECK ((presentation_type = ANY (ARRAY['article'::text, 'story'::text]))),
    CONSTRAINT admin_posts_story_url_check
        CHECK (presentation_type <> 'story' OR (story_url IS NOT NULL AND story_url LIKE 'https://%')),
    CONSTRAINT admin_posts_pinned_requires_home_check
        CHECK (NOT pinned_on_home OR show_on_home),
    CONSTRAINT admin_posts_story_version_check CHECK (story_version >= 1)
);

-- Keeps local databases created during development compatible while this
-- still-unreleased migration is repeatedly squashed and replayed.
ALTER TABLE public.admin_posts
    ADD COLUMN IF NOT EXISTS revision_number integer DEFAULT 1 NOT NULL;

CREATE TABLE IF NOT EXISTS public.admin_post_revisions (
    id uuid DEFAULT uuidv7() NOT NULL PRIMARY KEY,
    post_id uuid NOT NULL REFERENCES public.admin_posts(id) ON DELETE CASCADE,
    revision_number integer NOT NULL,
    snapshot jsonb NOT NULL,
    created_by text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE (post_id, revision_number)
);

CREATE TABLE IF NOT EXISTS public.admin_post_delivery_attempts (
    id uuid DEFAULT uuidv7() NOT NULL PRIMARY KEY,
    post_id uuid NOT NULL REFERENCES public.admin_posts(id) ON DELETE CASCADE,
    attempt_number integer NOT NULL,
    trigger text NOT NULL,
    eligible_count integer DEFAULT 0 NOT NULL,
    sent_count integer DEFAULT 0 NOT NULL,
    skipped_count integer DEFAULT 0 NOT NULL,
    status text NOT NULL,
    error_summary text DEFAULT ''::text NOT NULL,
    attempted_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE (post_id, attempt_number),
    CONSTRAINT admin_post_delivery_trigger_check
        CHECK (trigger = ANY (ARRAY['publish'::text, 'retry'::text, 'manual'::text])),
    CONSTRAINT admin_post_delivery_status_check
        CHECK (status = ANY (ARRAY['sent'::text, 'partial'::text, 'failed'::text, 'no_audience'::text]))
);

CREATE TABLE IF NOT EXISTS public.admin_notification_campaigns (
    id uuid DEFAULT uuidv7() NOT NULL PRIMARY KEY,
    campaign_key text NOT NULL UNIQUE,
    title text NOT NULL,
    body text NOT NULL,
    target_route text,
    platforms text[] DEFAULT '{ios,android,web}'::text[] NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    trigger_type text DEFAULT 'manual'::text NOT NULL,
    day_of_month integer,
    send_at timestamp with time zone,
    last_sent_at timestamp with time zone,
    created_by text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT admin_notification_campaign_status_check CHECK (status = ANY (ARRAY['draft'::text, 'scheduled'::text, 'sent'::text, 'paused'::text])),
    CONSTRAINT admin_notification_campaign_trigger_check CHECK (trigger_type = ANY (ARRAY['manual'::text, 'monthly'::text])),
    CONSTRAINT admin_notification_campaign_day_check CHECK (day_of_month IS NULL OR day_of_month BETWEEN 1 AND 28)
);

CREATE TABLE IF NOT EXISTS public.admin_campaign_delivery_attempts (
    id uuid DEFAULT uuidv7() NOT NULL PRIMARY KEY,
    campaign_id uuid NOT NULL REFERENCES public.admin_notification_campaigns(id) ON DELETE CASCADE,
    scheduled_for date NOT NULL,
    eligible_count integer DEFAULT 0 NOT NULL,
    sent_count integer DEFAULT 0 NOT NULL,
    skipped_count integer DEFAULT 0 NOT NULL,
    status text NOT NULL,
    attempted_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE (campaign_id, scheduled_for)
);

INSERT INTO public.admin_notification_campaigns
    (campaign_key, title, body, target_route, platforms, status, trigger_type, day_of_month, last_sent_at, created_by)
VALUES
    ('monthly-support', 'Support ClashKing', 'Monthly support helps keep ClashKing available and improving. Thank you.', '/settings/support', '{ios,android,web}', 'scheduled', 'monthly', 1, now(), 'system')
ON CONFLICT (campaign_key) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_admin_posts_status ON public.admin_posts (status);
CREATE INDEX IF NOT EXISTS idx_admin_posts_starts_at ON public.admin_posts (starts_at) WHERE status = 'scheduled';
CREATE INDEX IF NOT EXISTS idx_admin_posts_home_selection
    ON public.admin_posts (pinned_on_home DESC, priority DESC, published_at DESC)
    WHERE status = 'live' AND show_on_home = true;
CREATE INDEX IF NOT EXISTS idx_admin_post_revisions_post
    ON public.admin_post_revisions (post_id, revision_number DESC);
CREATE INDEX IF NOT EXISTS idx_admin_post_delivery_attempts_post
    ON public.admin_post_delivery_attempts (post_id, attempt_number DESC);
CREATE INDEX IF NOT EXISTS idx_admin_notification_campaigns_due
    ON public.admin_notification_campaigns (status, trigger_type, send_at);

-- +goose Down
DROP TABLE IF EXISTS public.admin_campaign_delivery_attempts;
DROP TABLE IF EXISTS public.admin_notification_campaigns;
DROP TABLE IF EXISTS public.admin_post_delivery_attempts;
DROP TABLE IF EXISTS public.admin_post_revisions;
DROP TABLE IF EXISTS public.admin_posts CASCADE;
DROP TABLE IF EXISTS public.mobile_notification_subscriptions;
DROP TABLE IF EXISTS public.mobile_notification_preferences;

ALTER TABLE public.mobile_push_devices
    DROP CONSTRAINT IF EXISTS mobile_push_devices_authorization_status_check,
    DROP COLUMN IF EXISTS authorization_status,
    DROP COLUMN IF EXISTS locale,
    DROP COLUMN IF EXISTS timezone;
