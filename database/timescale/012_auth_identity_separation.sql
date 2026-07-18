-- +goose Up
UPDATE public.auth_users
SET email_hash = NULL,
    password_hash = NULL,
    data = jsonb_set(
        (data - 'email_encrypted' - 'email_hash' - 'password')
            #- '{linked_accounts,email}',
        '{auth_methods}',
        COALESCE(
            (
                SELECT jsonb_agg(method)
                FROM jsonb_array_elements_text(COALESCE(data -> 'auth_methods', '[]'::jsonb)) AS methods(method)
                WHERE method <> 'email'
            ),
            '[]'::jsonb
        ),
        true
    ),
    updated_at = now()
WHERE COALESCE(data -> 'auth_methods', '[]'::jsonb) ? 'discord'
  AND (
      NOT (COALESCE(data -> 'auth_methods', '[]'::jsonb) ? 'email')
      OR user_id ~ '^[0-9]{15,20}$'
  );

-- +goose Down
-- Discord-provided email credentials cannot be reconstructed safely.
