-- +goose Up
ALTER TABLE public.mobile_push_devices
    ADD COLUMN IF NOT EXISTS authorization_status text DEFAULT 'not_determined' NOT NULL,
    ADD COLUMN IF NOT EXISTS locale text DEFAULT '' NOT NULL,
    ADD COLUMN IF NOT EXISTS timezone text DEFAULT '' NOT NULL;

ALTER TABLE public.mobile_push_devices
    DROP CONSTRAINT IF EXISTS mobile_push_devices_authorization_status_check;

ALTER TABLE public.mobile_push_devices
    ADD CONSTRAINT mobile_push_devices_authorization_status_check
    CHECK (authorization_status IN ('authorized', 'provisional', 'denied', 'not_determined'));

CREATE TABLE IF NOT EXISTS public.mobile_notification_preferences (
    id uuid DEFAULT uuidv7() PRIMARY KEY,
    user_id text NOT NULL,
    device_id text NOT NULL,
    environment text DEFAULT 'production' NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    locale text DEFAULT '' NOT NULL,
    timezone text DEFAULT '' NOT NULL,
    enabled_types text[] DEFAULT ARRAY[]::text[] NOT NULL,
    war_attack_modes text[] DEFAULT ARRAY[]::text[] NOT NULL,
    event_types text[] DEFAULT ARRAY[]::text[] NOT NULL,
    reminder_timings text[] DEFAULT ARRAY[]::text[] NOT NULL,
    account_scope text DEFAULT 'all' NOT NULL,
    selected_accounts text[] DEFAULT ARRAY[]::text[] NOT NULL,
    selected_town_halls integer[] DEFAULT ARRAY[]::integer[] NOT NULL,
    selected_clan_tags text[] DEFAULT ARRAY[]::text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT mobile_notification_preferences_environment_check
        CHECK (environment IN ('sandbox', 'production')),
    CONSTRAINT mobile_notification_preferences_account_scope_check
        CHECK (account_scope IN ('all', 'selected')),
    CONSTRAINT mobile_notification_preferences_selected_scope_check
        CHECK (account_scope <> 'selected' OR cardinality(selected_accounts) > 0),
    CONSTRAINT mobile_notification_preferences_user_device_environment_key
        UNIQUE (user_id, device_id, environment)
);

CREATE INDEX IF NOT EXISTS idx_mobile_notification_preferences_enabled
    ON public.mobile_notification_preferences (environment, enabled)
    WHERE enabled = true;

CREATE INDEX IF NOT EXISTS idx_mobile_notification_preferences_user_device
    ON public.mobile_notification_preferences (user_id, device_id);

CREATE INDEX IF NOT EXISTS idx_mobile_notification_preferences_types
    ON public.mobile_notification_preferences USING gin (enabled_types);

CREATE INDEX IF NOT EXISTS idx_mobile_notification_preferences_accounts
    ON public.mobile_notification_preferences USING gin (selected_accounts);

CREATE INDEX IF NOT EXISTS idx_mobile_notification_preferences_clans
    ON public.mobile_notification_preferences USING gin (selected_clan_tags);

CREATE TABLE IF NOT EXISTS public.mobile_notification_subscriptions (
    id uuid DEFAULT uuidv7() PRIMARY KEY,
    user_id text NOT NULL,
    device_id text NOT NULL,
    environment text DEFAULT 'production' NOT NULL,
    notification_type text NOT NULL,
    player_tag text DEFAULT '' NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT mobile_notification_subscriptions_environment_check
        CHECK (environment IN ('sandbox', 'production')),
    CONSTRAINT mobile_notification_subscriptions_identity_key
        UNIQUE (user_id, device_id, environment, notification_type, player_tag)
);

CREATE INDEX IF NOT EXISTS idx_mobile_notification_subscriptions_delivery
    ON public.mobile_notification_subscriptions (notification_type, environment, player_tag)
    WHERE enabled = true;

CREATE INDEX IF NOT EXISTS idx_mobile_notification_subscriptions_device
    ON public.mobile_notification_subscriptions (user_id, device_id, environment);

CREATE OR REPLACE VIEW public.mobile_notification_recipients
WITH (security_invoker = true) AS
SELECT
    s.id AS subscription_id,
    s.user_id,
    s.device_id,
    s.environment,
    s.notification_type,
    NULLIF(s.player_tag, '') AS selected_player_tag,
    COALESCE(NULLIF(s.player_tag, ''), pl.tag) AS resolved_player_tag,
    s.player_tag = '' AS all_accounts,
    s.settings,
    p.locale,
    p.timezone,
    d.id AS push_device_id,
    d.platform,
    d.provider,
    d.token_ciphertext,
    d.token_hash,
    d.app_version,
    d.build_number,
    d.last_seen_at
FROM public.mobile_notification_subscriptions s
JOIN public.mobile_notification_preferences p
  ON p.user_id = s.user_id
 AND p.device_id = s.device_id
 AND p.environment = s.environment
JOIN public.mobile_push_devices d
  ON d.user_id = s.user_id
 AND d.device_id = s.device_id
 AND d.environment = s.environment
LEFT JOIN public.player_links pl
  ON s.player_tag = ''
 AND pl.user_id = s.user_id
WHERE s.enabled = true
  AND p.enabled = true
  AND d.enabled = true
  AND d.authorization_status IN ('authorized', 'provisional');

COMMENT ON VIEW public.mobile_notification_recipients IS
    'Active push candidates. Empty subscription player_tag expands through player_links; resolved_player_tag remains NULL for global notifications when no account resolution is required.';

-- +goose Down
DROP VIEW IF EXISTS public.mobile_notification_recipients;

DROP TABLE IF EXISTS public.mobile_notification_subscriptions;
DROP TABLE IF EXISTS public.mobile_notification_preferences;

ALTER TABLE public.mobile_push_devices
    DROP CONSTRAINT IF EXISTS mobile_push_devices_authorization_status_check,
    DROP COLUMN IF EXISTS authorization_status,
    DROP COLUMN IF EXISTS locale,
    DROP COLUMN IF EXISTS timezone;
