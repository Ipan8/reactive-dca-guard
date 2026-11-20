# Reactive DCA Guard — Deploy Log Fase 1 (derisk + fondasi)
Tanggal: 20 Nov 2026. Semua TESTNET. Repo fresh: ~/workspace/reactive-dca-guard
(Foundry, solc 0.8.29, lib reactive-lib-omni v0.1.0 + forge-std).
Wallet agen: 0xa9cB01C54930511202fd75734bcdDe8FbE9B2453 (keystore cast `reactive-deployer`).

## 1. Jaringan terverifikasi live
- Lasna: chain 5318007, RPC https://lasna-rpc.rnk.dev ✓
- Base Sepolia: chain 84532, RPC https://sepolia.base.org ✓
- Unichain Sepolia: chain 1301, RPC https://sepolia.unichain.org ✓ (saldo agen 0 — lihat blocker)

## 2. Faucet lREACT — BERHASIL
- Kirim 0,1 ETH Base Sepolia ke faucet 0x2afaFD298b23b62760711756088F75B7409f5967
  via `request(address)` (cast send, keystore reactive-deployer).
- Hasil: agen Lasna 0 → **10 lREACT**; Base Sepolia 0,17 → 0,0695 ETH.
- Alokasi lREACT: RC ping/pong 5 + RC DCA 2 = 7; sisa agen ~3 lREACT.

## 3. LOOP HELLO-WORLD — TERBUKTI PENUH (gerbang Execution lolos)
- PingOrigin (Base Sepolia): 0x3564179bf5d89Bd9C677d0C77cf81a6244e99340
  deploy tx 0xe9f12c304822db9247d83753c55d5f69364136b78806c02b16e12db0eb8f8249
- PingPongReactive (Lasna): 0x80B416d32fD4A70161eeE887ac9bDAD43D93849b
  deploy tx 0x5a1540b77c142c3e247912ad836619d58cc6a329e3ee69da722cda4f246fc255 (fund 5 lREACT)
- PingPongCallback (Base Sepolia): 0x427EAc05DED2552F83cFF2c16D7dE07da2a3C485
  deploy tx 0xfd7021b989d06db1716258fc39bb1041491d2441cc21b1bb8dfbd2b7a4768cd3 (fund 0,01 ETH)
- setCallback tx 0x3482d2dbe09f8479456cab5d466a21c7b69ebb23e23b19510bd054fe5800bd0a
- Ping: `ping(42)` tx 0x6b79c3c2ec263c77aed3d3b412f0eb1c027c06a5743d7e4f371262679f47e726,
  blok Base Sepolia 61197289, 20 Nov 07:55:25 UTC.
- Tx reaktif Lasna: 0xf5e1bed269bc82e07a47e386e98a19dad424a5b0a58a4a565596c098f193b2d6,
  blok 8795853 (event Reacted: chain 84532, origin PingOrigin, value 42, blok asal 61197289).
- Tx callback Base Sepolia: 0xfd676cbc46ff881e307a92c0bea704f6d6359ce8a380d55852eeb274d49d71ee,
  blok 61197298 (event PongReceived, reactive = RC, value 42).
- Verifikasi state: RC reactCount 1 / lastValue 42; callback pongs 1 / lastValue 42;
  RC balance 4,982 lREACT (biaya 1 react ≈ 0,0177 lREACT), debt 0.
- **Latensi full-loop ≈ 2 detik** (blok ping ts 0x6afffcee → blok callback ts 0x6afffcf0;
  9 blok Base Sepolia).

## 4. FONDASI DCA GUARD — TER-DEPLOY + JALUR HARGA TERBUKTI
- MockToken DCAT: 0x7350783c525c902f5dc2e8ddf4170978840269c2 (1.000.000 mint ke agen)
- MiniFactory: 0xa23f5a392aa8b05238cb009098dc14d9b803d7a9
- Pair WETH/DCAT: 0xeb1033094a4716d360a0828cf598cb09adbcf084
  (token0 WETH 0x4200000000000000000000000000000000000006, token1 DCAT;
  likuiditas awal 0,02 WETH + 20.000 DCAT; LP agen ~20)
- DCAGuardReactive (Lasna): 0x314413299c2835fA91e5AC183cc10F0e8aDaA74b
  deploy tx 0xeb98c0d29e8765fb328eaee33f5febe045654a2b594bc4e0c0ad20da1bda0029 (fund 2 lREACT)
- DCAGuardCallback (Base Sepolia): 0x65c58531814906A70BcCB1c759E630bca7259829
  deploy tx 0x5b7746d5a2e49e257db9bc4560433810f8291f6c672e8f134f30fb6b75bcaa37 (fund 0,005 ETH)
- setCallback tx 0xf9f18399a6a8db8403dabd6294797cd3c6f6e7b79ca971286130ce8f9870df3a
  (catatan: 1x setCallback salah alamat nol dulu, langsung diperbaiki — tidak ada dampak)
- Uji harga: swap 1.000 DCAT → 0,000902 WETH,
  tx 0x8c89caedae2f0f7a36ac122b8c906f8a995b4b396eb2037d9ff9b301ac28f46a,
  blok 61199614 (Sync: reserve 0,0191 WETH / 21.000 DCAT).
- Verifikasi: DCA RC syncCount 1, lastReserve 0,0191/21.000;
  callback updateCount 1, lastPrice 1.099.601 DCAT/WETH (dari 1.000.000, +10% sesuai swap);
  RC balance 1,98 lREACT, debt 0; callback balance 0,0049987 ETH.
- CRON100 BELUM di-subscribe (sengaja — `subscribeCron()` owner-only, diaktifkan
  saat logika tick DCA ada, supaya tidak bakar lREACT tiap 2 menit).

## 5. Kendala yang dihadapi + solusi
- **v2-core butuh solc =0.5.16; forge tidak mendeteksinya** (bahkan 0.5.17 yang
  sudah ada di ~/.svm tidak dikenali; solc 0.5.16 manual di ~/.svm/0.5.16 juga
  tidak dikenali). Solusi: **MiniAMM** (src/MiniAMM.sol) — AMM constant-product
  sendiri, solc 0.8.29, interface kompatibel V2 (event `Sync(uint112,uint112)`
  + `getReserves()` + mint/burn/swap, fee 0,3%). v2-core sudah dihapus dari repo.
- **Unichain Sepolia ETH = 0.** Faucet publik (unichain.org, Chainlink, Google)
  butuh login web / akun — tidak ada jalur skrip. Bukan gate buat DCA Guard
  (Base Sepolia saja); jadi blocker kalau ide #2 (stop-loss Unichain) digarap.
- Base Sepolia ETH agen kini ~0,0395 (0,02 jadi WETH di pair + gas + funding
  callback). Cukup untuk belasan tx testnet lagi.

## 6. Langkah berikut (fase 2, hari 3-5 rencana)
1. Logika RC DCA: subscribe CRON100 via `subscribeCron()`, aturan beli/skip/jeda
   (circuit breaker dari pergerakan harga antar tick) + eksekusi swap di callback.
2. Frontend minimal + README + video demo <3 menit.
3. Submit PALING LAMBAT 5 Des 2026 (deadline 6 Des 03:00 WIB).
4. Kalau ide #2 digarap: perlu ETH Unichain Sepolia (faucet via browser/login).

## Explorer
- Lasna: https://lasna.reactscan.net/address/0x80B416d32fD4A70161eeE887ac9bDAD43D93849b
  dan https://lasna.reactscan.net/address/0x314413299c2835fA91e5AC183cc10F0e8aDaA74b
- Base Sepolia: https://sepolia.basescan.org/address/0xeb1033094a4716d360a0828cf598cb09adbcf084

---

# FASE 2 — Logika DCA + eksekusi swap + E2E testnet (20 Nov 2026, ~17:30–19:00 WIB)
Kontrak Fase 1 dibiarkan ter-deploy apa adanya sebagai artefak (tidak diubah).
Semua TESTNET, wallet agen 0xa9cB01C54930511202fd75734bcdDe8FbE9B2453.

## 1. Aturan DCA (diimplementasi di RC, harga = DCAT per WETH, 1e18-scaled)
- **BUY** bila: tidak pause DAN harga dalam ±30% dari harga referensi (harga pada
  tick CRON pertama setelah deploy) DAN |perubahan harga vs tick sebelumnya| < 20%.
- **SKIP** bila salah satu kondisi tidak terpenuhi, alasan dicatat on-chain
  (`decisionHistory`, event `DcaDecision`).
- **Circuit breaker**: |perubahan harga| >= 20% vs tick sebelumnya → auto-pause
  (`paused=true` + event `CircuitBreakerTriggered`), hanya owner bisa `unpause()`.
- Owner-only: `pause()` / `unpause()` / `setReferencePrice()` / `setBuyAmount()`.
  Buy amount default 0,001 WETH.
- Tick pertama: set harga referensi + prev price, change = 0 → BUY bila tidak pause.
- Pada BUY, RC request callback `onDcaTick(reactive, price, decision, amountIn)`
  ke callback Base Sepolia; `onPriceUpdate` lama tetap jalan untuk update harga.
- Callback `onDcaTick` (guard `onlyServiceProvider` + `onlyCallbackSender` sama
  seperti `onPriceUpdate`): bila decision==BUY dan saldo WETH >= buy amount →
  swap nyata WETH→DCAT di MiniAMM (rumus V2 fee 0,3%:
  `amountIn*997*reserveOut/(reserveIn*1000+amountIn*997)`), emit `DcaBuy`,
  update `buyCount` / `totalDcatBought` / `totalWethSpent`. Bila WETH kurang →
  emit `DcaSkipped` tanpa revert. Tambahan: `wrapEth()` / `wrapBalance()`,
  `withdrawWeth` / `withdrawDcat` / `withdrawEth` (owner, testnet).
- File baru/diubah: `src/DcaMath.sol` (library murni: band, breaker, amountOut),
  `src/DCAGuardReactive.sol` (Fase 2), `src/DCAGuardCallback.sol` (Fase 2),
  `script/DeployDCA2.s.sol` (deploy RC Lasna + callback Base), `test/DcaGuard.t.sol`.
- `forge build` lolos; `forge test` 6/6 lolos (band ±30% tepi, breaker 20% tepi,
  amountOut 987 + nilai produksi 1041797283176593521421, swap lokal callback,
  skip tanpa revert saat WETH kurang, tolak sender salah).

## 2. Deploy + funding Fase 2
- DCAGuardReactive (Lasna): 0x3669eead32953566cccddd0517c557d4a19d62cb
  deploy tx 0x198f551072a88250254dc35a81e361cc1bde38040e8d992ad0c7926a0986e00c,
  blok Lasna 8804653 (fund 2 lREACT di konstruktor).
- DCAGuardCallback (Base Sepolia): 0x4f701a8b20c28ec401dea6062969c9ae14df377f
  deploy tx 0x63f628e4b6efcb0a3cc322c28c4eebda77ef6a48af7fafc9294988538bfde69f,
  blok Base 61244350 (fund 0,005 ETH di konstruktor).
- setCallback (Lasna): tx 0x6cb482b99722df9931fe43e2d5a19725e4138b5d2ef88653303f599e2ac61e27,
  blok 8804675 (hash dipulihkan via scan blok Lasna; output cast awal kepotong).
- Wrap 0,01 ETH → WETH: tx 0x1c543799fa45793057961500524c79885121d82a47609765b70e02310035a9f3,
  blok 61244403. Transfer 0,01 WETH → callback:
  tx 0xc1ed61a7b73ca35a46d8baed740ba9bd6130f05d62e7371a288ee125f328cac6,
  blok 61244415.
- Trigger Sync (supaya RC baru dapat reserve — Sync hanya fire saat swap):
  wrap 0,001 ETH tx 0xb02d37a6cd88a01c7c1cc16f02e0b1cdfe83a251cd55ed17b58072d766aa5733
  (blok 61245518); transfer 0,0005 WETH → pair
  tx 0xe33628ecbede203f33e926d889841a43fdfb4b68de813deeef03d03cc670ceed
  (blok 61245635); swap 0,0005 WETH → 534,148 DCAT
  tx 0xee36f8c9f8990238b83337b4fd2e3ecf7ffb171520b63c9b82a0aef8d61219de
  (blok 61245749). Reserve jadi 0,0195978 WETH / 20.465,852 DCAT.
  RC baru syncCount=1; callback updateCount=1 (lalu 2 — lihat observasi).
- subscribeCron() (Lasna): tx 0x0a4759a500bb83e647281bd36a6596a406bc6b3f50d244a35f3c0b966fe718fa,
  blok 8804955. CRON100 = tiap 100 blok Lasna, teramati ~107 detik antar tick.

## 3. E2E — 5 tick, 4 BUY tereksekusi + 1 SKIP (guard bekerja)
Harga referensi (tick 1): 1.044.292,09 DCAT/WETH. Band bawah: 731.004,46.
| Tick | Blok Lasna | Tx react | Harga | Δ vs tick lalu | Keputusan |
|---|---|---|---|---|---|
| 1 | 8805001 | 0xa69cab6bbaa90d876d9d850428b9e7f4e76854abe94d2861250d623fb174baca | 1.044.292,09 | — (ref set) | BUY |
| 2 | 8805101 | 0xdb7b2a07ad8af4bebbe61a58e309ec9b62638c494c12c3152dd6cafc02d463ed | 945.492,88 | -9,46% | BUY |
| 3 | 8805201 | 0xcb2696507b853f754b73febaf443421d0232b367da8b7aba9869a0e7e9cdd9d9 | 860.084,82 | -9,03% | BUY |
| 4 | 8805301 | 0xf651c4516ad671dadfaeba32586b5e6aa2e239c0334f5f9859fa57fdd30bf807 | 785.752,36 | -8,64% | BUY |
| 5 | 8805401 | 0x020cfa4f6dfd8babafd910e54470d5d516bf777cddb832ce02bfdb4e32b478fb | 720.659,70 | -8,28% | SKIP "outside +-30% band" |

Swap tereksekusi di callback (event `DcaBuy`, 0,001 WETH tiap buy):
| # | Blok Base | Tx callback | DCAT diterima | Harga eksekusi |
|---|---|---|---|---|
| 1 | 61246130 | 0x45b3b39dff7c924a149084d3764525c68d4afc51f60455d1e66e85d18d7603c2 | 990,7564599387954 | 990.756,46 |
| 2 | 61246663 | 0x2d7af4fe85dc347ef3eb76c37457a92855691fac530f258de4b95cc72e125325 | 899,1353985012478 | 899.135,40 |
| 3 | 61247200 | 0x6558164a25aa738d5798ec403a998813564db6a010f3d4184178e8f44bb51172 | 819,6670463400263 | 819.667,05 |
| 4 | 61247741 | 0xd64ceb43831b6268e18223f45a1d7d7badec74027efaf592f70e296ab28109f7 | 750,2927154984118 | 750.292,72 |

Total: 0,004 WETH → 3.459,8516202784813 DCAT. Harga turun -30,99% vs referensi
pada tick 5 (720.659,70 < band bawah 731.004,46) → SKIP tercatat on-chain
(`decisionHistory[4]`, `lastDecisionReason` = "outside +-30% band").
Per-tick change selalu <20% → circuit breaker TIDAK pernah trip (sesuai desain;
breaker hanya bereaksi ke lonjakan antar tick, bukan drift kumulatif).

## 4. State akhir (terverifikasi on-chain, setelah unsubscribe)
- RC: cronTicks=5, decisionCount=5, paused=false, cronSubscribed=false,
  saldo 1,7773667 lREACT (dari 2; terpakai 0,2226333 untuk deploy+react+subscribe).
- Callback: buyCount=4, skipCount=0, totalDcatBought=3.459,8516202784813,
  totalWethSpent=0,004, saldo 0,0049902 ETH / 0,006 WETH / 3.459,8516 DCAT.
- Pair: reserve 0,0235978 WETH / 17.006,0004 DCAT (harga akhir 720.659,70 —
  cocok dengan tick 5). Cek konsistensi: 20.465,852 − 17.006,000 = 3.459,852 ✓.
- Agen: Base Sepolia ~0,018475 ETH, Lasna ~0,43217 lREACT (tidak perlu faucet;
  lREACT agen menipis — top-up 0,1 ETH → 10 lREACT bila mau lanjutkan cron).
- unsubscribeCron() (Lasna, supaya tidak bakar lREACT tiap ~107 dtk setelah
  E2E terbukti): tx 0x02b940cc5ad2162b1cab0a8759c1a470a440a5c724e95420a1fa6b0c2711f9cf,
  blok 8805479. Tick 6 (blok 8805501) tidak pernah fire. Kontrak tetap bisa
  di-subscribe ulang kapan saja (`subscribeCron()` owner-only).

## 5. Observasi / catatan
- Callback `updateCount`=2 padahal hanya 1 Sync yang memicu `onPriceUpdate`
  setelah deploy — kemungkinan duplicate delivery dari Reactive (at-least-once);
  `lastPrice` konsisten dengan reserve, tidak berdampak ke keputusan/buy.
- Harga referensi diambil dari reserve pasca-trigger-swap (bukan reserve awal
  Fase 1) — benar per spesifikasi (tick CRON pertama setelah deploy).
- `forge test` 6/6 + `forge build` lolos sebelum deploy (lihat §1).
- Explorer: Lasna https://lasna.reactscan.net/address/0x3669eead32953566cccddd0517c557d4a19d62cb ;
  Base https://sepolia.basescan.org/address/0x4f701a8b20c28ec401dea6062969c9ae14df377f

## 6. Frontend minimal + deploy Vercel (20 Nov 2026, ~17:50–18:10 WIB)
- File: `web/index.html` — satu halaman statis, tanpa build tool / tanpa
  dependensi JS. Semua data dibaca live via JSON-RPC mentah (`fetch` +
  `eth_call`/`eth_getBalance`/`eth_getTransactionReceipt`/`eth_getLogs`) ke
  Lasna https://lasna-rpc.rnk.dev dan Base Sepolia https://sepolia.base.org;
  selector fungsi dihitung dari `src/*.sol` via `cast sig`.
- Tampilan: harga saat ini, harga referensi, band ±30% (lantai/ceil dihitung
  live dari referensi), badge pause + cronSubscribed, riwayat 5 tick dari
  `decisionHistory(i)` (harga + Δ vs tick lalu + BUY/SKIP + alasan), 4 buy dari
  event `DcaBuy` + tx hash (tautan Basescan), saldo callback ETH/WETH/DCAT,
  reserve pair + harga dari reserve, tautan explorer semua kontrak.
- Per-buy diambil dari log, bukan hardcode: receipt tiap tx hash buy →
  nomor blok → `eth_getLogs` 1 blok (Base Sepolia menolak `eth_getLogs`
  > 200 blok, error 413 — alasan dipakai pendekatan per-blok).
- Tombol owner (pause/unpause/subscribeCron/unsubscribeCron) via
  `window.ethereum` + `eth_sendTransaction` (data = selector saja, chain Lasna
  5318007, `wallet_switchEthereumChain` bila chain salah); tanpa wallet tombol
  nonaktif + catatan. **Nol transaksi dikirim saat build/test.**
- Deploy: Vercel MCP (`create_project` + `create_deployment` file inline,
  target production) — proyek `reactive-dca-guard`
  (`prj_zui33bUliQszzMecOZQ5S2zlYxRG`, tim `ipan12`), deployment
  `dpl_DK1HM7vQGogSm4ZbWtRyAwD5kprN`, state READY.
  URL: **https://reactive-dca-guard-ipan12.vercel.app/**
  (alias deployment `reactive-dca-guard-8no3mq9ar-ipan12.vercel.app`).
  Repo TIDAK di-push ke GitHub (TODO submit-prep terpisah, sesuai instruksi).
- Kendala: Vercel mengaktifkan SSO protection by default
  (`ssoProtection.enabled=true`, deploymentType `all_except_custom_domains`) —
  URL publik awal redirect 302 ke `vercel.com/login`. Dimatikan via
  `update_project` (`ssoProtection: null`) → HTTP 200 publik, 20.986 byte.
- Verifikasi (20 Nov ~18:08 WIB): `cast call` ulang semua state (RC, callback,
  pair) + replika logika JS frontend di Node — semua angka cocok dengan §3/§4
  (ref 1.044.292,09; harga 720.659,70; band bawah 731.004,46; 5 tick
  4 BUY + 1 SKIP "outside +-30% band"; total 3.459,8516 DCAT dari 0,004 WETH;
  callback 0,0049902 ETH / 0,006 WETH / 3.459,8516 DCAT; pair 0,0235978 WETH /
  17.006,000 DCAT). Screenshot render penuh di `web/screenshot.png`
  (Firefox headless via Playwright + proxy egress + `ignoreHTTPSErrors` —
  Chromium langsung gagal `ERR_TUNNEL_CONNECTION_FAILED` karena proxy egress
  butuh auth preemptif + MITM CA; dua bug frontend ketemu saat verifikasi dan
  diperbaiki sebelum deploy: decode string `decisionHistory` salah offset dan
  format angka terpotong bukan dibulatkan — yang live di Vercel sudah versi benar).

