SELECT *
FROM {{ source('tasty_bytes_raw', 'MENU') }}
