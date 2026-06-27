select 
*

from {{ source('tasty_bytes_raw', 'CUSTOMER_LOYALTY') }}
-- this is a test edit
