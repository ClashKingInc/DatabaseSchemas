-- +goose Up
ALTER TABLE public.server_logs RENAME TO server_logs_legacy;

CREATE TABLE public.server_logs (
    server_id text NOT NULL REFERENCES public.servers(id) ON DELETE CASCADE,
    clan_tag text,
    type text NOT NULL,
    webhook_id text NOT NULL,
    thread_id text,
    active_war_id text,
    active_raid_id text,
    message_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT server_logs_type_check CHECK (type = ANY (ARRAY[
        'join_log', 'leave_log', 'donation_log',
        'clan_achievement_log', 'clan_requirements_log', 'clan_description_log',
        'war_log', 'war_panel', 'cwl_lineup_change_log',
        'capital_donations', 'capital_attacks', 'raid_panel', 'capital_weekly_summary',
        'role_change', 'troop_upgrade', 'super_troop_boost', 'th_upgrade',
        'league_change', 'spell_upgrade', 'hero_upgrade',
        'hero_equipment_upgrade', 'name_change',
        'legend_log_attacks', 'legend_log_defenses'
    ])),
    CONSTRAINT server_logs_webhook_id_check CHECK (btrim(webhook_id) <> ''),
    CONSTRAINT server_logs_clan_fkey FOREIGN KEY (clan_tag, server_id)
        REFERENCES public.server_clans(tag, server_id) ON DELETE CASCADE,
    CONSTRAINT server_logs_scope_type_key
        UNIQUE NULLS NOT DISTINCT (server_id, clan_tag, type)
);

CREATE INDEX idx_server_logs_scope ON public.server_logs (server_id, clan_tag, type);
CREATE INDEX idx_server_logs_webhook ON public.server_logs (webhook_id);

INSERT INTO public.server_logs (server_id, clan_tag, type, webhook_id, thread_id)
SELECT legacy.server_id,
       scope.clan_tag,
       expanded.type,
       legacy.webhook_id,
       legacy.thread_id
FROM public.server_logs_legacy legacy
LEFT JOIN public.server_log_clans scope
    ON scope.server_id = legacy.server_id AND scope.log_type = legacy.log_type
CROSS JOIN LATERAL unnest(
    CASE legacy.log_type
        WHEN 'join_leave_log' THEN ARRAY['join_log', 'leave_log']::text[]
        WHEN 'capital_donation_log' THEN ARRAY['capital_donations']::text[]
        WHEN 'capital_raid_log' THEN ARRAY['capital_attacks']::text[]
        WHEN 'player_upgrade_log' THEN ARRAY[
            'role_change', 'troop_upgrade', 'super_troop_boost', 'th_upgrade',
            'league_change', 'spell_upgrade', 'hero_upgrade',
            'hero_equipment_upgrade', 'name_change'
        ]::text[]
        WHEN 'legend_log' THEN ARRAY['legend_log_attacks', 'legend_log_defenses']::text[]
        ELSE ARRAY[legacy.log_type]::text[]
    END
) AS expanded(type)
WHERE legacy.enabled = true
  AND COALESCE(btrim(legacy.webhook_id), '') <> ''
ON CONFLICT (server_id, clan_tag, type) DO UPDATE SET
    webhook_id = EXCLUDED.webhook_id,
    thread_id = EXCLUDED.thread_id,
    updated_at = now();

INSERT INTO public.server_logs (
    server_id, clan_tag, type, webhook_id, thread_id,
    active_war_id, active_raid_id, message_id
)
SELECT server_id,
       clan_tag,
       CASE type
           WHEN 'join' THEN 'join_log'
           WHEN 'leave' THEN 'leave_log'
           WHEN 'donations' THEN 'donation_log'
           WHEN 'war' THEN 'war_log'
           WHEN 'capital' THEN 'capital_attacks'
           ELSE type
       END,
       webhook_token,
       thread_id,
       active_war_id,
       active_raid_id,
       message_id
FROM public.clan_logs
WHERE COALESCE(btrim(webhook_token), '') <> ''
ON CONFLICT (server_id, clan_tag, type) DO UPDATE SET
    webhook_id = EXCLUDED.webhook_id,
    thread_id = EXCLUDED.thread_id,
    active_war_id = EXCLUDED.active_war_id,
    active_raid_id = EXCLUDED.active_raid_id,
    message_id = EXCLUDED.message_id,
    updated_at = now();

DROP TABLE public.server_log_clans;
DROP TABLE public.server_logs_legacy;
DROP TABLE public.clan_logs;

-- +goose Down
-- +goose StatementBegin
DO $$
BEGIN
    RAISE EXCEPTION 'migration 020 is irreversible because it merges server_logs and clan_logs';
END
$$;
-- +goose StatementEnd
