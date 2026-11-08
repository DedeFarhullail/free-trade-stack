# free-trade-stack

Zero-cost crypto research + swap-quote stack. Every data source is **free, keyless,
and needs no account**. No Clawby, no subscription, no API key, no signup.

One bash script. 14 commands. 6 free data providers. Verified live.

```
$ ./scripts/free_trade.sh doctor

ENDPOINT HEALTH  all should be free + keyless
──────────────────────────────────────────────────────────────────
  ✓ GMGN openapi       code=0 (auth OK)
  ✓ DexScreener        HTTP 200
  ✓ GeckoTerminal      HTTP 200
  ✗ ParaSwap           HTTP 404          ← see note below
  ✓ Li.Fi              HTTP 200
  ✓ Binance public     HTTP 200
  ✓ BSC public RPC     HTTP 200
```

---

## Install

```bash
git clone https://github.com/BOZAGENTIC/free-trade-stack.git
cd free-trade-stack
chmod +x scripts/free_trade.sh
./scripts/free_trade.sh doctor
```

Dependencies: `bash`, `curl`, `jq`, `python3`. Nothing else.

---

## Commands

| Command | What it does |
|---|---|
| `doctor` | Health-check every free endpoint |
| `scan <token> [chain]` | All-in-one: info + security audit + pool + liquidity + CEX anchor |
| `audit <token> [chain]` | Security: tax, honeypot, blacklist, renounced, liquidity lock, concentration, risk flags |
| `info <token> [chain]` | Fundamentals: supply, holders, liquidity, price history, buy/sell activity |
| `pool <token> [chain]` | Biggest pool: reserves, liquidity, quote token |
| `holders <token> [chain]` | Top holders + top traders |
| `kline <token> [res] [chain] [days]` | OHLCV candles (30s/1m/5m/15m/1h/4h/1d) |
| `liquidity <token> [chain]` | DexScreener pairs + GeckoTerminal pools |
| `quote <from> <to> <amt> [chain]` | Swap quote from ParaSwap + Li.Fi, cross-checked against baw |
| `price <symbol>` | Binance 24h ticker |
| `ckline <symbol> [iv] [n]` | Binance OHLCV candles |
| `trending` | GeckoTerminal trending pools |
| `balance [chain]` | baw wallet balances (needs baw login) |
| `chains` | Chains baw supports |

Chain arg accepts a numeric ID (`56`, `1`, `137`, `8453`, `42161`, `501`) or a GMGN
chain name (`bsc`, `eth`, `base`, `sol`). Default `56`.

### Examples

```bash
# Screen a token before you touch it
./scripts/free_trade.sh scan 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82 bsc

# Is it a honeypot? Hidden tax? Ownership renounced?
./scripts/free_trade.sh audit 0xe071F5AA90F211A0824e717f1569060193679Ce6 bsc

# Who holds it, who's trading it
./scripts/free_trade.sh holders 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82 bsc

# What would I actually receive on a swap
./scripts/free_trade.sh quote 0xbb4CdB9Cbd36B01bD1cBaEBF2De08d9173bc095c \
                              0x55d398326f99059fF775485246999027B3197955 1 56

# Price action
./scripts/free_trade.sh kline 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82 1h bsc 7
./scripts/free_trade.sh price BNBUSDT
```

---

## Data sources

| Source | Auth | What it gives |
|---|---|---|
| **GMGN openapi** | public demo key `gmgn_solbscbaseethmonadtron` | token info, security, pool, top holders, top traders, kline |
| **DexScreener** | none | DEX pairs, liquidity, volume, price change |
| **GeckoTerminal** | none | pools, trending, OHLCV |
| **ParaSwap** | none | EVM swap quotes, best-price routing |
| **Li.Fi** | none | EVM swap + cross-chain bridge quotes |
| **Binance public** | none | CEX reference price + klines |

Override the GMGN demo key with your own (free at [gmgn.ai/ai](https://gmgn.ai/ai)):

```bash
export GMGN_API_KEY=your_key_here
```

---

## Sample output

```
$ ./scripts/free_trade.sh audit 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82 bsc

SECURITY AUDIT  0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82  (chain bsc)
──────────────────────────────────────────────────────────────────
  FLAGS
  ✓ not a honeypot
  ✓ no blacklist
  ✓ contract open source
  ✓ ownership renounced

  TAX
  buy tax                0%
  sell tax               0%
  avg / high             0% / 0%
  can sell               0

  CONCENTRATION
  top10 holder rate      3.2%
  burn ratio             0.0%
  dev burn ratio         0.0%

  LIQUIDITY LOCK
  locked                 yes
  lock percent           95.0%
  left unlocked          5.0%
  risk flags             none
  privileges             none
```

```
$ ./scripts/free_trade.sh quote 0xbb4CdB9Cbd36B01bD1cBaEBF2De08d9173bc095c \
                                0x55d398326f99059fF775485246999027B3197955 1 56

SWAP QUOTE  0xbb4CdB9Cbd36B01bD1cBaEBF2De08d9173bc095c → 0x55d398326f99059fF775485246999027B3197955  amount=1  chain=56
──────────────────────────────────────────────────────────────────
  ✓ ParaSwap
    you receive          698.524457 0x55d398326f99059fF775485246999027B3197955
    USD value            697.8874030730
    before fee           698.539094
```

---

## GMGN auth — the non-obvious part

GMGN is **not** a plain bearer-token API. Every request needs three things:

```bash
curl "https://openapi.gmgn.ai/v1/token/security?chain=bsc&address=0x...&timestamp=<unix>&client_id=<uuid>" \
     -H "X-APIKEY: <key>"
```

- Header name is `X-APIKEY` — not `X-API-Key`, not `Authorization`
- `timestamp` = unix seconds; server validates within ±5s
- `client_id` = UUID; replays rejected within 7s
- Swap/order routes additionally need `X-Signature` (Ed25519 or RSA-SHA256 over
  `{sub_path}:{sorted_query}:{body}:{timestamp}`). Read routes do not.

Endpoints that work with the public demo key:

```
/v1/token/info
/v1/token/security
/v1/token/pool_info
/v1/market/token_top_holders
/v1/market/token_top_traders
/v1/market/token_kline        ← params: resolution + from/to in MILLISECONDS
```

Endpoints that return empty on the demo key: `/v1/market/rank`, `/v1/trenches` (POST only).

---

## Pitfalls

- **GMGN rate limit is 5 req/sec per IP.** Hammering it gets the IP temporarily
  banned (~30 min) with `RATE_LIMIT_BANNED`. `scan` makes 4+ calls — don't loop it.
- **ParaSwap nests everything under `.delta`** — `.delta.destAmount`,
  `.delta.receivedDestUSD`, `.delta.destAmountBeforeFee`. A top-level `.destAmount`
  check silently reports "no route".
- **Li.Fi does not index WBNB** (`0xbb4CdB9Cbd36B01bD1cBaEBF2De08d9173bc095c`) on
  chain 56. Use the native placeholder `0x0000...0000` instead — that works.
- **GMGN kline takes `resolution`, not `interval`**, and `from`/`to` are milliseconds.
- `jq -e '.code == 0'` is the success gate for GMGN — a non-zero code still returns HTTP 200.
- Use `curl -G --data-urlencode` to build these GET query strings. Hand-encoding
  breaks on mixed-case addresses.
- `doctor` reports ParaSwap as HTTP 404 because `/chains/56` isn't a real route —
  the quote endpoint itself works fine. It's a health-check artifact, not a bug.

---

## What this stack does NOT do

It **researches and quotes**. It does not execute. To actually trade:

- **baw** — `baw market-order swap/quote`. 7 chains (BSC, ETH, Base, Polygon,
  Arbitrum, Robinhood, Solana). Custodial, login via Binance App QR.
- **evm_tx.py** — raw EVM signing from a BIP-39 phrase or private key, for chains
  baw doesn't cover (Elysium, HyperEVM, any EVM chain).

Quotes are indicative. Re-quote immediately before execution.

---

## What genuinely costs money

- **Fast RPC for sniping** — Geyser/shreds on Solana, or a dedicated node. Public
  RPC will skip the blocks you care about. This is the only unavoidable cost.
- **Trading fees** — DEX ~0.25%, CEX ~0.075% with BNB discount. Per-trade, not a subscription.

Everything else here is free.

---

## As an agent skill

`SKILL.md` in this repo is a drop-in agent skill (Hermes / Claude Code / Codex /
Cursor / Cline). It documents the commands, the GMGN auth quirk, and the pitfalls
so an agent doesn't re-derive them.

---

## License

MIT
