# Reactive DCA Guard — SUBMIT-READY (Fase 2, kontrak + E2E)

Status: **kontrak + E2E testnet SELESAI dan terverifikasi on-chain (20 Nov 2026)**.
Frontend + video demo: TODO (dikerjakan worker lain — lihat §5).
Deadline submit: **6 Des 2026 03:00 WIB**. Semua testnet, tidak ada mainnet.

## 1. Apa itu DCA Guard

Auto-DCA + circuit breaker di atas Reactive Network (track **Set It and Forget It**).
Reactive contract di Lasna memantau pair WETH/DCAT (MiniAMM sendiri, kompatibel
Uniswap V2) di Base Sepolia; tiap tick CRON100 (~107 detik) ia memutuskan
BUY / SKIP dengan aturan eksplisit, dan saat BUY, callback di Base Sepolia
mengeksekusi swap nyata WETH → DCAT.

Aturan keputusan (harga = DCAT per WETH, 1e18-scaled):
- **BUY**: tidak pause DAN harga dalam ±30% dari harga referensi (harga tick CRON
  pertama) DAN |perubahan harga vs tick sebelumnya| < 20%.
- **SKIP**: salah satu kondisi gagal — alasan dicatat on-chain (`decisionHistory`,
  event `DcaDecision`).
- **Circuit breaker**: |perubahan harga| >= 20% vs tick sebelumnya → auto-pause,
  hanya owner yang bisa `unpause()`.
- Buy amount default 0,001 WETH (owner bisa `setBuyAmount()`).

## 2. Kontrak (testnet)

| Kontrak | Chain | Alamat |
|---|---|---|
| DCAGuardReactive (Fase 2) | Lasna 5318007 | 0x3669eead32953566cccddd0517c557d4a19d62cb |
| DCAGuardCallback (Fase 2) | Base Sepolia 84532 | 0x4f701a8b20c28ec401dea6062969c9ae14df377f |
| Pair WETH/DCAT (MiniAMM) | Base Sepolia 84532 | 0xeb1033094A4716d360A0828cf598cB09adbCF084 |
| DCAT (MockToken) | Base Sepolia 84532 | 0x7350783C525C902f5dC2e8dDF4170978840269C2 |
| WETH | Base Sepolia 84532 | 0x4200000000000000000000000000000000000006 |
| MiniFactory | Base Sepolia 84532 | 0xa23f5a392aa8b05238cb009098dc14d9b803d7a9 |
| Callback proxy (sistem) | Base Sepolia 84532 | 0x476F44b11F5C942c58f4c8E3d0300E5710743585 |
| System contract (sistem) | Lasna 5318007 | 0x8888888888888888888888888888888888888888 |

Kontrak Fase 1 (RC 0x314413299c2835fA91e5AC183cc10F0e8aDaA74b,
callback 0x65c58531814906A70BcCB1c759E630bca7259829) tetap ter-deploy sebagai artefak.
Repo: `~/workspace/reactive-dca-guard/` — `src/DcaMath.sol`,
`src/DCAGuardReactive.sol`, `src/DCAGuardCallback.sol`,
`script/DeployDCA2.s.sol`, `test/DcaGuard.t.sol`.
`forge build` lolos; `forge test` 6/6 lolos (band ±30%, breaker 20%, rumus
amountOut V2 0,3%, swap lokal, skip tanpa revert, tolak sender salah).
Log lengkap: `DEPLOY-LOG-FASE-1.md` (§ Fase 2).

## 3. Bukti E2E (semua tx hash terverifikasi on-chain)

Deploy & setup:
- RC deploy (fund 2 lREACT): 0x198f551072a88250254dc35a81e361cc1bde38040e8d992ad0c7926a0986e00c (Lasna blok 8804653)
- Callback deploy (fund 0,005 ETH): 0x63f628e4b6efcb0a3cc322c28c4eebda77ef6a48af7fafc9294988538bfde69f (Base blok 61244350)
- setCallback: 0x6cb482b99722df9931fe43e2d5a19725e4138b5d2ef88653303f599e2ac61e27 (Lasna blok 8804675)
- Wrap 0,01 ETH → WETH: 0x1c543799fa45793057961500524c79885121d82a47609765b70e02310035a9f3 (blok 61244403)
- Transfer 0,01 WETH → callback: 0xc1ed61a7b73ca35a46d8baed740ba9bd6130f05d62e7371a288ee125f328cac6 (blok 61244415)
- Trigger Sync (swap 0,0005 WETH → 534,148 DCAT): 0xee36f8c9f8990238b83337b4fd2e3ecf7ffb171520b63c9b82a0aef8d61219de (blok 61245749)
- subscribeCron: 0x0a4759a500bb83e647281bd36a6596a406bc6b3f50d244a35f3c0b966fe718fa (Lasna blok 8804955)

Hasil 5 tick (harga referensi 1.044.292,09 DCAT/WETH):
- Tick 1–4: BUY — harga 1.044.292,09 → 945.492,88 → 860.084,82 → 785.752,36
  (per-tick -9,46% / -9,03% / -8,64%, semua dalam band & di bawah breaker).
- Tick 5: **SKIP "outside +-30% band"** — harga 720.659,70, turun -30,99% vs
  referensi (di bawah lantai band 731.004,46). Guard terbukti menghentikan
  pembelian, bukan sekadar membeli terus.
- Tx react tiap tick (Lasna): 0xa69cab6bbaa90d876d9d850428b9e7f4e76854abe94d2861250d623fb174baca,
  0xdb7b2a07ad8af4bebbe61a58e309ec9b62638c494c12c3152dd6cafc02d463ed,
  0xcb2696507b853f754b73febaf443421d0232b367da8b7aba9869a0e7e9cdd9d9,
  0xf651c4516ad671dadfaeba32586b5e6aa2e239c0334f5f9859fa57fdd30bf807,
  0x020cfa4f6dfd8babafd910e54470d5d516bf777cddb832ce02bfdb4e32b478fb.

Swap tereksekusi (event `DcaBuy`, 0,001 WETH per buy, Base Sepolia):
- 0x45b3b39dff7c924a149084d3764525c68d4afc51f60455d1e66e85d18d7603c2 — 990,756 DCAT (blok 61246130)
- 0x2d7af4fe85dc347ef3eb76c37457a92855691fac530f258de4b95cc72e125325 — 899,135 DCAT (blok 61246663)
- 0x6558164a25aa738d5798ec403a998813564db6a010f3d4184178e8f44bb51172 — 819,667 DCAT (blok 61247200)
- 0xd64ceb43831b6268e18223f45a1d7d7badec74027efaf592f70e296ab28109f7 — 750,293 DCAT (blok 61247741)
- **Total: 0,004 WETH → 3.459,8516 DCAT.** Reserve pair bergerak
  0,0195978 WETH / 20.465,852 DCAT → 0,0235978 WETH / 17.006,000 DCAT
  (selisih DCAT = total dibeli, cocok persis).

State akhir: RC cronTicks=5, decisionCount=5, saldo 1,7773667 lREACT;
callback buyCount=4, skipCount=0, saldo 0,0049902 ETH / 0,006 WETH / 3.459,8516 DCAT.
CRON di-unsubscribe setelah E2E terbukti (tx 0x02b940cc5ad2162b1cab0a8759c1a470a440a5c724e95420a1fa6b0c2711f9cf,
Lasna blok 8805479) supaya tidak bakar lREACT; bisa di-subscribe ulang kapan saja.

Explorer: https://lasna.reactscan.net/address/0x3669eead32953566cccddd0517c557d4a19d62cb
dan https://sepolia.basescan.org/address/0x4f701a8b20c28ec401dea6062969c9ae14df377f

## 4. Yang belum / catatan

- Circuit breaker belum pernah trip live (per-tick change maks -9,46% selama E2E);
  logikanya teruji di `forge test` (tepi 20% persis) dan siap didemokan dengan
  menggeser harga >20% dalam satu tick (swap besar) bila diperlukan.
- Callback `updateCount`=2 padahal 1 Sync pemicu — kemungkinan duplicate delivery
  Reactive; tidak berdampak ke keputusan/buy (harga konsisten).
- Saldo agen menipis: Lasna ~0,43 lREACT, Base ~0,0185 ETH. Untuk demo lanjutan
  (subscribe ulang / buy lagi), top-up via faucet: kirim 0,1 Sepolia ETH ke
  0x2afaFD298b23b62760711756088F75B7409f5967 → 10 lREACT.

## 5. TODO — Frontend + video (worker lain)

- [x] Frontend minimal — **SELESAI 20 Nov 2026 ~18:08 WIB, terverifikasi live.**
  URL deploy (Vercel, publik): **https://reactive-dca-guard-ipan12.vercel.app/**
  (alias deployment `reactive-dca-guard-8no3mq9ar-ipan12.vercel.app`, proyek Vercel
  `reactive-dca-guard` id `prj_zui33bUliQszzMecOZQ5S2zlYxRG`, tim `ipan12`,
  deployment id `dpl_DK1HM7vQGogSm4ZbWtRyAwD5kprN`, target production).
  Static satu halaman (`web/index.html`, tanpa build tool / tanpa dependensi —
  JSON-RPC mentah ke Lasna + Base Sepolia, selector dihitung dari `src/*.sol`).
  Menampilkan live: harga saat ini, harga referensi, band ±30% (lantai 731.004,46),
  status pause + cronSubscribed, riwayat 5 tick dari `decisionHistory`, 4 buy dari
  event `DcaBuy` (via receipt → `eth_getLogs` 1 blok, karena Base Sepolia membatasi
  `eth_getLogs` ≤ 200 blok) + tx hash, saldo callback (ETH/WETH/DCAT), reserve pair.
  Tombol owner (pause/unpause/subscribeCron/unsubscribeCron) via injected wallet
  (Lasna 5318007); tanpa wallet tombol nonaktif — **tidak ada transaksi yang
  dikirim saat build/test**. Verifikasi: HTTP 200 publik (SSO protection Vercel
  yang aktif by default sudah dimatikan via `update_project`), semua angka di
  screenshot cocok persis dengan §3 (harga 720.659,70; ref 1.044.292,09;
  5 tick 4 BUY + 1 SKIP; total 3.459,8516 DCAT; reserve 0,0235978 / 17.006,000).
  Bukti: `web/screenshot.png`. Catatan: repo belum di-push ke GitHub (TODO submit-prep
  terpisah) — deploy dilakukan via Vercel MCP `create_deployment` file inline,
  bukan via Git.
- [ ] README repo: tambah bagian Fase 2 + tautan explorer (sebagian sudah di
  `DEPLOY-LOG-FASE-1.md`).
- [x] Video demo < 3 menit: alur tick → BUY → swap → SKIP saat harga jatuh
  di bawah band (pakai tx hash di §3 sebagai bukti). — **SELESAI 20 Nov 2026 ~18:25 WIB.**
  File: `~/workspace/reactive-dca-guard/demo-video-reactive.mp4`
  (1280×720, H.264 + AAC, durasi 167,48 dtk / 2 mnt 47 dtk, 10,5 MB).
  Bahasa Inggris, narasi TTS (gTTS) + teks overlay. Isi 9 segmen: judul → masalah/solusi
  (auto-DCA + breaker ±30% / 20%) → tur frontend live (harga 720.659,70; ref
  1.044.292,09; lantai band 731.004,46) → riwayat 5 tick (4 BUY + tick 5 SKIP
  "outside +-30% band") → 4 swap nyata 0,001 WETH (total 0,004 WETH →
  3.459,8516 DCAT) → saldo callback + reserve pair (0,0235978 WETH /
  17.006,000 DCAT) → kartu bukti 4 tx hash swap + blok → kartu kontrak
  (RC 0x3669…62cb, callback 0x4f70…377f, pair 0xeb10…CF084) + catatan jujur
  breaker belum pernah trip live (Forge 6/6) → penutup submit-ready, deadline
  6 Des. Screenshot frontend diambil FRESH dari URL live via Playwright Firefox
  (9 cek angka DOM cocok persis dengan §3); TIDAK ada transaksi baru untuk video
  (CRON tetap off). Verifikasi: ffprobe (video+audio 167,48 dtk, mean vol -22,3 dB)
  + 8 frame sampel ditonton, semua terbaca bersih. Build script:
  `demo-video/` (`shoot.py`, `build_cards.py`, `tts.py`, `narration.txt`,
  `build_video.py`, `shots/`, `cards/`, `audio/`, `segments/`, `check/`).
- [ ] Submit ke Reactive Omni Buildathon paling lambat 5 Des 2026
  (deadline 6 Des 03:00 WIB) — JANGAN submit sebelum frontend + video beres.
