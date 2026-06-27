SELECT *
FROM {{ source('tasty_bytes_raw', 'ORDER_DETAIL') }}
