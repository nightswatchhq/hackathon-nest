# hackathon-nest

A [Nuthatch](https://github.com/nightswatchhq/nuthatch) starter for hackathon builders on
**Sepolia** and **Arc Testnet**. One binary, one command, your contract's events in a local SQL
database with an HTTP API in front of it. No API key, no query quota, no rate limit, nothing to sign
up for.

It exists because testnet subgraphs are served from Subgraph Studio's development endpoint, which
is rate-limited by design, and a front end polling a few times a second burns through that in
under an hour. A nest does not care how often you ask.

The honest framing: if you are in a Graph prize track, the judges want to see the subgraph doing
the work in the demo. Use the nest for the build-and-test loop, where you query hundreds of times
an hour, and keep the subgraph for the demo. Or run both and fall back to the nest if the quota dies
mid-judging.

## 1. Install

```sh
curl -fsSL https://nuthatch-indexer.com/install.sh | sh
```

Prebuilt binary for macOS Apple Silicon and Linux x86_64, installed to `~/.local/bin`. No compiler.

## 2. Run this starter (about a minute)

```sh
nuthatch init --from https://github.com/nightswatchhq/hackathon-nest
nuthatch dev --dir hackathon-nest
```

`dev` backfills Sepolia USDC from the pinned start block, prints "caught up to tip", and serves an
API on `http://127.0.0.1:8288`. It is also the serve command; leave it running. In a second terminal:

```sh
nuthatch sql --dir hackathon-nest "SELECT * FROM recent_transfers LIMIT 5"
nuthatch sql --dir hackathon-nest "SELECT * FROM top_recipients"
nuthatch sql --dir hackathon-nest            # a REPL: .tables, .schema usdc__transfer
```

Measured on 2026-09-11 from this repo's pinned start block: 1,086 blocks, 4,016 transfers, ready in under 5 seconds.

## 3. Swap in your own contract

### From your subgraph (the short path)

You already have a subgraph deployed to Studio, so you have a **deployment ID** (`Qm...`, on the
subgraph's Studio page). The manifest it points at pins every ABI and start block, and Nuthatch
reads it directly:

```sh
nuthatch init --from-subgraph QmYourDeploymentId \
  --chain sepolia --rpc https://ethereum-sepolia-rpc.publicnode.com \
  --dir my-nest
nuthatch dev --dir my-nest
```

What carries across: every `dataSource` becomes a contract, every `template` becomes a template,
ABIs are vendored from IPFS, `startBlock` is kept, and the handler list becomes the event allowlist.
The import prints a report of what it mapped and what it skipped. Read it.

What does not carry across automatically, because the manifest does not contain it. Each has a
config equivalent you write by hand:

- **Mapping logic.** A nest gives you one table per event, exactly as emitted. Entities your
  mapping derived from several events become SQL views (see `views/` here). Most hackathon
  mappings are a `GROUP BY` in disguise.
- **Contract calls in handlers.** A `[[calls]]` block with `on = "<table>"` fires one `eth_call`
  per row at the row's block, arguments taken from the row's columns, the same thing
  `contract.balanceOf(event.params.to)` does in a mapping. Needs `nuthatch dev --state-rpc <url>`
  with an endpoint that serves state at those blocks; the Sepolia endpoint here prunes state about
  a million blocks behind tip, which is months of hackathon.
- **Call handlers.** `[extract] top_level_calls = true` decodes transactions sent to your contracts.
  Block handlers have no equivalent; the contract will index every event its ABI defines instead,
  narrowed with `events = [...]`.
- **File data sources.** A `[[ipfs]]` block resolves the documents a column's CIDs name, given
  `--ipfs <gateway>`. Without one the CID is stored as a column and nothing is fetched.
- **Factory templates need a creating event.** The manifest cannot say which event spawns a
  template, so the report will tell you to add a `[[factories]]` block naming it.

### From an address

```sh
nuthatch init 0xYourContract --chain sepolia \
  --rpc https://ethereum-sepolia-rpc.publicnode.com \
  --abi ./path/to/YourContract.json --alias mycontract --dir my-nest
```

Pass `--abi`. Sepolia contracts are rarely verified on Sourcify, and the Etherscan fallback needs
`ETHERSCAN_API_KEY` set. A Foundry `out/YourContract.sol/YourContract.json` or a Hardhat
`artifacts/...json` works as is: Nuthatch reads the `abi` field out of the artifact (verified 2026-09-11).

Adding a second contract to an existing nest is `nuthatch add 0xOther --abi ./Other.json --dir my-nest`.

## 4. Arc Testnet

Arc is not in Nuthatch's built-in chain registry, so name it and give it an endpoint. Nuthatch reads
the chain id from the RPC (5042002) and treats it as a conservative L1: 64 blocks to finality and a
narrow log window.

```sh
nuthatch init --from-subgraph QmYourArcDeploymentId \
  --chain arc-testnet --rpc https://rpc.testnet.arc.network --dir my-arc-nest
nuthatch dev --dir my-arc-nest --window 80
```

Measured against `https://rpc.testnet.arc.network` on 2026-09-11 with `nuthatch doctor`: `eth_getLogs`
up to 160 blocks in a range-only probe, JSON-RPC batches of 200 fine, and HTTP 429 on rapid probes.
So start with `--window 80`, leave `--concurrency` at its default of 1, and re-probe with your own
address before a long backfill, because an address-filtered window is usually much wider:

```sh
nuthatch doctor --rpc https://rpc.testnet.arc.network --address 0xYourContract
```

Arc's tip was at block 61.5M with sub-second blocks, so a backfill "from deployment" for a contract
deployed weeks ago is a real backfill. Prefer `--backfill 50000` (blocks back from tip) while iterating.

One chain per process. A Sepolia nest and an Arc nest are two `nuthatch dev` runs on two ports
(`--listen 127.0.0.1:8289` for the second).

## 5. Query it from your app

The API is plain HTTP and returns JSON. Read-only SQL:

```sh
curl -G http://127.0.0.1:8288/sql \
  --data-urlencode 'q=SELECT "from", "to", value_dec / 1000000 AS usdc FROM usdc__transfer ORDER BY block_number DESC LIMIT 20'
```

```json
{"rows":[...],"count":20,"provenance":{"as_of":11681079,"sealed_through":11681015,"source":"hot+sealed"},"truncated":false}
```

Tables are `{alias}__{event}`, all lower snake case. `GET /tables` lists them with columns,
`GET /schema` explains them. Two things every first query trips over:

- `from` and `to` are SQL reserved words. Double-quote them.
- `uint256` columns are exact text. Use the `_dec` companion (`value_dec`) for sums and comparisons.

**Stop polling on a timer.** Sepolia produces a block every 12 seconds; asking seven times in five
seconds gets the same answer seventeen times per block. `GET /ready` is cheap and carries
`last_block`; poll that, and run your real queries only when it moves. Better still, subscribe to
`newHeads` on your RPC websocket and query once per block. This is what fixes the Studio quota
too, if you keep the subgraph in the loop.

**CORS.** The nest sets no `Access-Control-Allow-Origin` header, so a browser page on another
origin cannot call it directly. Call it from your server side (a Next.js route handler, an Express
route) and return the rows to the page, which is where an API key would live anyway. If you must
hit it from the browser, put a reverse proxy in front that adds the header.

There is also an MCP server (`nuthatch mcp`) if you are building with a coding agent; the scaffolded
`.claude/skills/nuthatch/` tells the agent how to query this nest.

## 6. Letting the judges in

`dev` is the serve command, so a demo box is one process. On any small VPS:

```sh
nuthatch dev --dir my-nest --listen 0.0.0.0:8288 --no-admin
```

Put a reverse proxy with TLS in front (Caddy is one line: `reverse_proxy :8288`), and either pass
`--no-admin` as above or set `NUTHATCH_ADMIN_TOKEN`; off localhost the admin UI refuses to serve
without it. The `/sql` endpoint has its own guards (a query timeout, a row cap, a concurrency cap)
that protect the box from a runaway query; they are not rate limits on you. systemd and Docker
recipes are in
[`docs/operators.md`](https://github.com/nightswatchhq/nuthatch/blob/main/docs/operators.md).

A cheaper option for a one-week demo is a tunnel from your laptop (`cloudflared tunnel --url
http://127.0.0.1:8288`), with the obvious caveat that the laptop has to stay open.

## RPC endpoints, measured

Every keyless Sepolia endpoint was probed with `nuthatch doctor` on 2026-09-11. Only one passed:

| Endpoint | Result |
| --- | --- |
| `ethereum-sepolia-rpc.publicnode.com` | getLogs up to 2,560 blocks, batching fine, no archive state. **Used here.** |
| `sepolia.drpc.org` | "chain is not available on free plan" |
| `1rpc.io/sepolia` | getLogs capped at 10 blocks, then usage limit |
| `rpc.sepolia.org` | HTTP 404 |
| `sepolia.gateway.tenderly.co` | transport error |
| `eth-sepolia.public.blastapi.io` | transport error |

Public endpoints rot; that table has an expiry date. A free Alchemy or Infura Sepolia key is the
reliable option, and it never has to touch this repo: `nuthatch dev --rpc https://your-endpoint`
overrides `rpc_urls` at runtime without editing the config.

## What is in here

| File | What |
| --- | --- |
| `nuthatch.toml` | The nest: chain, endpoint, one contract, two events. |
| `abis/usdc.json` | A minimal ERC-20 ABI (Transfer, Approval). |
| `views/10-recent-transfers.sql` | The last 100 transfers in whole USDC. |
| `views/20-top-recipients.sql` | The 20 biggest recipients since `start_block`. |
| `semantic.toml` | What the tables and views mean, for `/schema` and the MCP. |
| `schema.json`, `llms.txt` | Generated by `nuthatch schema`; regenerate after editing the config. |

`nuthatch check` validates views against the tables the config produces. Run it after editing
either, before you spend a backfill finding out.

## Help

The [Night's Watch Discord](https://discord.gg/CQewvyJ69Y) is where the people who run these sit.
Subgraph questions that are not about Nuthatch go to
[nightswatchhq/graph-support](https://github.com/nightswatchhq/graph-support).
