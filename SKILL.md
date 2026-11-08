---
name: free-trade-stack
description: Use when researching or quoting crypto tokens/swaps without paying for any data subscription. Runs free_trade.sh — token security audit, fundamentals, holders, kline, liquidity, and swap quotes from GMGN/DexScreener/GeckoTerminal/ParaSwap/Li.Fi/Binance, all keyless.
---

# Free Trade Stack

Zero-cost crypto research + swap-quote stack. Every data source is free, keyless,
and needs no account. No Clawby, no subscription, no API key.

**Script:** `scripts/free_trade.sh` (also installed at `~/.hermes/scripts/free_trade.sh`)

## When to use

- Screening a token before minting/buying (agentic NFT projects, memecoins, any BSC/EVM token)
- Checking whether a token is a honeypot / has hidden tax / is renounced
- Getting a swap quote without a paid aggregator key
- Cross-checking DEX liquidity against CEX reference price
- Any time the operator asks for token data and you'd otherwise reach for a paid API

## Commands

```
free_trade.sh doctor                              # endpoint health check
free_trade.sh scan   <token> [chain]              # all-in-one: info+audit+pool+liquidity+CEX
free_trade.sh audit  <token> [chain]              # security: tax, honeypot, blacklist, renounce, lock
free_trade.sh info   <token> [chain]              # fundamentals: supply, holders, liquidity, activity
free_trade.sh pool   <token> [chain]              # biggest pool reserves
free_trade.sh holders <token> [chain]             # top holders + top traders
free_trade.sh kline  <token> [res] [chain] [days] # OHLCV candles
free_trade.sh liquidity <token> [chain]           # DexScreener + GeckoTerminal pairs/pools
free_trade.sh quote  <from> <to> <amt> [chain]    # ParaSwap + Li.Fi + baw cross-check
free_trade.sh price  <symbol>                     # Binance 24h ticker
free_trade.sh ckline <symbol> [iv] [n]            # Binance OHLCV
free_trade.sh trending                            # GeckoTerminal trending pools
free_trade.sh balance [chain]                     # baw wallet balances (needs baw login)
free_trade.sh chains                              # baw supported chains
```

Chain arg accepts either a numeric ID (`56`, `1`, `137`, `8453`, `42161`, `501`) or a
GMGN chain name (`bsc`, `eth`, `base`, `sol`). Default `56`.

## Data sources (all verified live)

| Source | Auth | What it gives |
|---|---|---|
| GMGN openapi | public demo key `gmgn_solbscbaseethmonadtron` | token info, security, pool, top holders, top traders, kline |
| DexScreener | none | DEX pairs, liquidity, volume, price change |
| GeckoTerminal | none | pools, trending, OHLCV |
| ParaSwap | none | EVM swap quotes, best-price routing |
| Li.Fi | none | EVM swap + cross-chain bridge quotes |
| Binance public | none | CEX reference price + klines |

## GMGN auth detail (the non-obvious part)

GMGN is NOT a plain bearer-token API. Every request needs:

```
GET https://openapi.gmgn.ai/v1/token/security?chain=bsc&address=0x...&timestamp=<unix>&client_id=<uuid>
Header: X-APIKEY: <key>
```

- Header name is `X-APIKEY` (not `X-API-Key`, not `Authorization`)
- `timestamp` = unix seconds, server validates within ±5s
- `client_id` = UUID, replays rejected within 7s
- Swap/order routes additionally need `X-Signature` (Ed25519 or RSA-SHA256 over
  `{sub_path}:{sorted_query}:{body}:{timestamp}`) — read routes do not

Endpoints that work with the public demo key:
`/v1/token/info`, `/v1/token/security`, `/v1/token/pool_info`,
`/v1/market/token_top_holders`, `/v1/market/token_top_traders`,
`/v1/market/token_kline` (params: `resolution` + `from`/`to` in **milliseconds**).

Endpoints that return empty on the demo key: `/v1/market/rank` (needs `order_by`,
still empty), `/v1/trenches` (POST only).

## Pitfalls

- **GMGN rate limit is 5 req/sec per IP.** Hammering it gets the IP temporarily
  banned (~30 min) with `RATE_LIMIT_BANNED`. Space calls out; `scan` makes 4+ calls,
  so don't run it in a tight loop.
- **ParaSwap response nests everything under `.delta`** — `.delta.destAmount`,
  `.delta.receivedDestUSD`, `.delta.destAmountBeforeFee`. A top-level `.destAmount`
  check silently fails and reports "no route".
- **Li.Fi does not index WBNB** (`0xbb4CdB9Cbd36B01bD1cBaEBF2De08d9173bc095c`) on
  chain 56. Use the native placeholder `0x0000...0000` instead — that works.
- **GMGN kline takes `resolution`, not `interval`**, and `from`/`to` are milliseconds.
- `jq -e '.code == 0'` is the success gate for GMGN; a non-zero code still returns HTTP 200.
- `curl -G --data-urlencode` is the correct way to build these GET query strings —
  do not hand-encode, addresses with mixed case break it.
- baw cross-check in `quote` only works when baw is logged in; otherwise it warns
  and continues.

## Execution layer (separate from this skill)

This stack only researches and quotes. To actually trade:

- **baw** — `baw market-order swap/quote`, 7 chains (BSC, ETH, Base, Polygon,
  Arbitrum, Robinhood, Solana). Custodial, login via Binance App QR.
- **evm_tx.py** (`~/.hermes/scripts/evm_tx.py`) — raw EVM signing from a BIP-39
  phrase or private key, for chains baw doesn't cover (e.g. Elysium, HyperEVM).
  Always preview before `--yes`.

## What genuinely costs money

- Fast RPC for sniping (Geyser/shreds on Solana, or a dedicated node). Public RPC
  will skip the blocks you care about. This is the only unavoidable cost.
- Trading fees (DEX ~0.25%, CEX ~0.075% with BNB discount) — per-trade, not a subscription.

Everything else in this stack is free.
