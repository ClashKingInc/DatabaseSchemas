-- +goose Up
ALTER TABLE public.role_rules DROP CONSTRAINT role_rules_type_check;
ALTER TABLE public.role_rules DROP CONSTRAINT role_rules_mode_check;

DELETE FROM public.role_rules
WHERE type = 'ignored'
   OR (type = 'family' AND option = 'only_family')
   OR (type = 'clan_role' AND option = 'member' AND clan_tag IS NULL);

DELETE FROM public.role_rules duplicate
USING public.role_rules canonical
WHERE duplicate.server_id = canonical.server_id
  AND duplicate.clan_tag IS NOT DISTINCT FROM canonical.clan_tag
  AND duplicate.type = 'family'
  AND duplicate.option = 'member'
  AND canonical.type = 'family'
  AND canonical.option = 'family'
  AND duplicate.role_id = canonical.role_id;

UPDATE public.role_rules
SET option = 'family', updated_at = now()
WHERE type = 'family' AND option = 'member';

UPDATE public.role_rules
SET mode = 'both', updated_at = now()
WHERE mode = 'sync';

ALTER TABLE public.role_rules ALTER COLUMN mode SET DEFAULT 'both';
ALTER TABLE public.role_rules RENAME TO server_roles;

ALTER TABLE public.server_roles RENAME CONSTRAINT role_rules_pkey TO server_roles_pkey;
ALTER TABLE public.server_roles RENAME CONSTRAINT role_rules_server_id_fkey TO server_roles_server_id_fkey;
ALTER TABLE public.server_roles RENAME CONSTRAINT role_rules_clan_fkey TO server_roles_clan_fkey;
ALTER TABLE public.server_roles RENAME CONSTRAINT role_rules_scope_check TO server_roles_scope_check;
ALTER TABLE public.server_roles RENAME CONSTRAINT role_rules_option_check TO server_roles_option_check;
ALTER TABLE public.server_roles RENAME CONSTRAINT role_rules_role_id_check TO server_roles_role_id_check;
ALTER TABLE public.server_roles RENAME CONSTRAINT role_rules_server_id_clan_tag_type_option_role_id_key TO server_roles_server_id_clan_tag_type_option_role_id_key;

ALTER INDEX public.idx_role_rules_server_type RENAME TO idx_server_roles_server_type;
ALTER INDEX public.idx_role_rules_clan RENAME TO idx_server_roles_clan;

ALTER TABLE public.server_roles
    ADD CONSTRAINT server_roles_type_check CHECK (type = ANY (ARRAY[
        'townhall', 'builderhall', 'league', 'builder_league',
        'clan_role', 'clan_category', 'family', 'achievement', 'status'
    ])),
    ADD CONSTRAINT server_roles_mode_check CHECK (mode = ANY (ARRAY['add', 'remove', 'both']));

-- +goose Down
ALTER TABLE public.server_roles DROP CONSTRAINT server_roles_type_check;
ALTER TABLE public.server_roles DROP CONSTRAINT server_roles_mode_check;
ALTER TABLE public.server_roles ALTER COLUMN mode SET DEFAULT 'sync';

UPDATE public.server_roles
SET mode = 'sync', updated_at = now()
WHERE mode = 'both';

ALTER INDEX public.idx_server_roles_server_type RENAME TO idx_role_rules_server_type;
ALTER INDEX public.idx_server_roles_clan RENAME TO idx_role_rules_clan;

ALTER TABLE public.server_roles RENAME CONSTRAINT server_roles_pkey TO role_rules_pkey;
ALTER TABLE public.server_roles RENAME CONSTRAINT server_roles_server_id_fkey TO role_rules_server_id_fkey;
ALTER TABLE public.server_roles RENAME CONSTRAINT server_roles_clan_fkey TO role_rules_clan_fkey;
ALTER TABLE public.server_roles RENAME CONSTRAINT server_roles_scope_check TO role_rules_scope_check;
ALTER TABLE public.server_roles RENAME CONSTRAINT server_roles_option_check TO role_rules_option_check;
ALTER TABLE public.server_roles RENAME CONSTRAINT server_roles_role_id_check TO role_rules_role_id_check;
ALTER TABLE public.server_roles RENAME CONSTRAINT server_roles_server_id_clan_tag_type_option_role_id_key TO role_rules_server_id_clan_tag_type_option_role_id_key;

ALTER TABLE public.server_roles RENAME TO role_rules;

ALTER TABLE public.role_rules
    ADD CONSTRAINT role_rules_type_check CHECK (type = ANY (ARRAY[
        'townhall', 'builderhall', 'league', 'builder_league',
        'clan_role', 'clan_category', 'family', 'achievement',
        'status', 'ignored'
    ])),
    ADD CONSTRAINT role_rules_mode_check CHECK (mode = ANY (ARRAY['add', 'remove', 'sync']));
