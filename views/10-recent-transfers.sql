-- The last 100 USDC transfers, newest first, with the amount in whole USDC.
-- "from" and "to" are SQL reserved words, hence the quotes; value is exact text
-- (uint256), so arithmetic uses its value_dec companion.
CREATE VIEW recent_transfers AS
  SELECT block_number,
         block_timestamp,
         tx_hash,
         "from",
         "to",
         value_dec / 1000000 AS usdc
  FROM "usdc__transfer"
  ORDER BY block_number DESC, log_index DESC
  LIMIT 100;
