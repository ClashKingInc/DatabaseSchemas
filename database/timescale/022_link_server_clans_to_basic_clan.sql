-- +goose Up
DELETE FROM public.server_clans sc
WHERE NOT EXISTS (
    SELECT 1
    FROM public.basic_clan clan
    WHERE clan.tag = sc.tag
);

ALTER TABLE public.server_clans
    ADD CONSTRAINT server_clans_basic_clan_fkey
    FOREIGN KEY (tag) REFERENCES public.basic_clan(tag) ON DELETE CASCADE;

-- +goose Down
ALTER TABLE public.server_clans
    DROP CONSTRAINT server_clans_basic_clan_fkey;
