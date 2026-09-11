-- The 20 addresses that received the most USDC since start_block.
CREATE VIEW top_recipients AS
  SELECT "to" AS addr,
         count(*) AS transfers,
         sum(value_dec) / 1000000 AS usdc
  FROM "usdc__transfer"
  GROUP BY "to"
  ORDER BY usdc DESC
  LIMIT 20;
