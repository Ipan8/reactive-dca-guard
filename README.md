# DCA Guard — Reactive Omni Buildathon (testnet only)

Auto-DCA + circuit breaker di atas Reactive Network (track **Set It and Forget It**).
Repo FRESH, dibangun selama event. Deadline submit: **6 Des 2026 03:00 WIB**.

## Status — Fase 1 SELESAI (20 Nov 2026)
- ✅ Loop hello-world Lasna→Base Sepolia **terbukti on-chain, latensi ≈ 2 detik**
  (ping 42 → react → pong 42; tx hash lengkap di `DEPLOY-LOG-FASE-1.md`).
- ✅ Fondasi DCA Guard ter-deploy: AMM sendiri (MiniAMM, kompatibel V2) +
  pair WETH/DCAT berlikuiditas + RC Sync-subscriber + callback pencatat harga.
  Jalur harga terbukti: swap geser harga +10% → RC syncCount 1 → callback
  updateCount 1, lastPrice 1.099.601 DCAT/WETH.
- ✅ **Fase 2 SELESAI (20 Nov 2026)**: logika DCA + swap nyata + E2E — 5 tick
  CRON, 4 BUY tereksekusi (0,004 WETH → 3.459,85 DCAT, tx hash di
  `DEPLOY-LOG-FASE-1.md` § Fase 2), tick ke-5 SKIP "outside +-30% band"
  (harga -30,99% vs referensi) — guard terbukti. `forge test` 6/6.
  RC Fase 2: 0x3669eead32953566cccddd0517c557d4a19d62cb (Lasna),
  callback Fase 2: 0x4f701a8b20c28ec401dea6062969c9ae14df377f (Base Sepolia).
  CRON di-unsubscribe setelah E2E (bisa subscribe ulang). Detail submit:
  `SUBMIT-READY-FASE-2.md`.
- ⏳ Berikutnya: frontend minimal → video demo <3 menit → submit (deadline 6 Des 2026 03:00 WIB).

## Kontrak (testnet)
| Kontrak | Chain | Alamat |
|---|---|---|
| PingOrigin | Base Sepolia 84532 | 0x3564179bf5d89Bd9C677d0C77cf81a6244e99340 |
| PingPongReactive | Lasna 5318007 | 0x80B416d32fD4A70161eeE887ac9bDAD43D93849b |
| PingPongCallback | Base Sepolia 84532 | 0x427EAc05DED2552F83cFF2c16D7dE07da2a3C485 |
| MockToken DCAT | Base Sepolia 84532 | 0x7350783c525c902f5dc2e8ddf4170978840269c2 |
| MiniFactory | Base Sepolia 84532 | 0xa23f5a392aa8b05238cb009098dc14d9b803d7a9 |
| Pair WETH/DCAT | Base Sepolia 84532 | 0xeb1033094a4716d360a0828cf598cb09adbcf084 |
| DCAGuardReactive | Lasna 5318007 | 0x314413299c2835fA91e5AC183cc10F0e8aDaA74b |
| DCAGuardCallback | Base Sepolia 84532 | 0x65c58531814906A70BcCB1c759E630bca7259829 |

## Build / deploy
```bash
export PATH="$HOME/.foundry/bin:$PATH"
forge build
forge script script/DeployDCA.s.sol:DeployDCA --rpc-url https://sepolia.base.org \
  --account reactive-deployer --password-file ~/.agent-wallets/reactive-deployer.pw --broadcast
```
Keystore `reactive-deployer` = wallet agen (jangan pernah print key-nya).
Faucet lREACT: `cast send 0x2afaFD298b23b62760711756088F75B7409f5967 "request(address)" <addr> --value 0.1ether` (Base Sepolia, 0,1 ETH = 10 lREACT).

## Catatan
- MiniAMM dipakai karena stock Uniswap v2-core butuh solc =0.5.16 yang tidak bisa
  dipakai toolchain sandbox ini (lihat DEPLOY-LOG-FASE-1.md §5). Interface-nya
  kompatibel V2 (event `Sync(uint112,uint112)`, `getReserves`, mint/burn/swap, fee 0,3%).
- CRON100 sengaja belum di-subscribe (`subscribeCron()` owner-only) supaya tidak
  bakar lREACT sebelum logika tick ada.
- Testnet SAJA. Tidak ada mainnet, tidak ada uang beneran.
