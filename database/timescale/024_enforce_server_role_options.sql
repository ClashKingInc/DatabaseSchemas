-- +goose Up
ALTER TABLE public.server_roles
    ADD CONSTRAINT server_roles_supported_option_check CHECK (
        (type <> 'family' OR (clan_tag IS NULL AND option = ANY (ARRAY['family', 'not_family'])))
        AND
        (type <> 'clan_role' OR (
            option = ANY (ARRAY['member', 'elder', 'co_leader', 'leader'])
            AND NOT (clan_tag IS NULL AND option = 'member')
        ))
    );

-- +goose Down
ALTER TABLE public.server_roles
    DROP CONSTRAINT server_roles_supported_option_check;
