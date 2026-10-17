

# boosterpak NEWS

## v0.9.3 (2026-10-17)

#### New features

- add attach_mode = “interactive” and use it in scaffold-analysis
  ([c7e422b](https://github.com/seanthimons/boosterpak/tree/c7e422b070d862a4d7eef0f7199ba9d341f22a49))
- list attach sources, upgrade need, and GitHub token visibility
  ([5dbb89b](https://github.com/seanthimons/boosterpak/tree/5dbb89bd140f72c60396ff76dccd4d38d8496fd4))
- add upgrade_project() with dry-run lockfile preview and rate-limit
  hints
  ([ea3efac](https://github.com/seanthimons/boosterpak/tree/ea3efac44c0be2038442ce7ebe27fba2c5f667b4))
- warn in check_binary_repos() when curl cannot follow redirects
  ([6ffe5b8](https://github.com/seanthimons/boosterpak/tree/6ffe5b81302475875a1406b92ad8c298d219e493))
- add check_binary_repos() to verify Package Manager serves binaries
  ([16bef5b](https://github.com/seanthimons/boosterpak/tree/16bef5b4e89638f33d8dfb9b49e9c858e9d00dbb))
- send the R user agent header for curl and wget downloads
  ([a8e5325](https://github.com/seanthimons/boosterpak/tree/a8e5325f8ac803596aba57c7c57b4aa04ef849ad))
- recognize p3m.dev and self-hosted Package Manager hosts
  ([7e48cde](https://github.com/seanthimons/boosterpak/tree/7e48cdeae273803b1fe68158e52c82561820c137))

#### Bug fixes

- keep package repository names when snapshotting on Linux
  ([d678730](https://github.com/seanthimons/boosterpak/tree/d6787301c4979cc2c21d92b1f15c480b9a33cfed))
- restore the Package Manager CRAN URL after renv activation on every OS
  ([affc728](https://github.com/seanthimons/boosterpak/tree/affc728347637aa3f4ce34bc1aa9ae835a4462e7))
- declare rlang in Imports and explain lockfile mirrors in project
  sessions
  ([cf0f672](https://github.com/seanthimons/boosterpak/tree/cf0f6725195aff17605470e40ba675637a835828))
- catch attach failures per package and match only real TOML table
  headers
  ([0fff5b0](https://github.com/seanthimons/boosterpak/tree/0fff5b0fb80dc62d1daabf55c4094d6efbe9a030))
- regenerate attach.R and prune settings on remove_pack, track
  boosters_version
  ([f73cb75](https://github.com/seanthimons/boosterpak/tree/f73cb75df61cf637189bb18dbcf31e864c34a9bc))
- re-apply Linux binary repos after renv activation and guard attach.R
  ([aee0f2f](https://github.com/seanthimons/boosterpak/tree/aee0f2fd8ee14a96765e7d3e14e5400f90e75566))

#### Tests

- use valid file URLs in the package index test on Windows
  ([363ad79](https://github.com/seanthimons/boosterpak/tree/363ad79a7b8056deda059d07c1c16ae7fbac4a05))

#### Docs

- document attach_mode and the CRAN default-mirror restore
  ([e33f5b8](https://github.com/seanthimons/boosterpak/tree/e33f5b8f87b90b1bcb0868c78602479bf70e30de))
- add upgrade, Linux, rate-limit and startup-cost guidance and the R
  manager crosswalk
  ([0fff517](https://github.com/seanthimons/boosterpak/tree/0fff517f94fb06f64d92a7b525d4d2739f53bd06))
- explain the portable Linux binary setup
  ([3121b84](https://github.com/seanthimons/boosterpak/tree/3121b84f67ae56b64c98ac58569896be69471dfd))

#### Other changes

- bump version to 0.9.3 \[skip ci\]
  ([2dfec62](https://github.com/seanthimons/boosterpak/tree/2dfec620d2fc1ccf199f28ced4da37193783d802))

Full set of changes:
[`v0.9.2...v0.9.3`](https://github.com/seanthimons/boosterpak/compare/v0.9.2...v0.9.3)

## v0.9.2 (2026-10-05)

#### Bug fixes

- use manylinux PPM binaries on Linux (#23)
  ([c7d3d59](https://github.com/seanthimons/boosterpak/tree/c7d3d5992924cad02809b5f1e8f460104f13cec8))

#### Docs

- update NEWS.md for v0.9.2 \[skip ci\]
  ([98834f2](https://github.com/seanthimons/boosterpak/tree/98834f26135d75de15ca1ce032c612e7c65094d5))

#### Other changes

- bump version to 0.9.2 \[skip ci\]
  ([774e48f](https://github.com/seanthimons/boosterpak/tree/774e48f61bc5487c2554b45bda72cd5a09307000))

Full set of changes:
[`v0.9.1...v0.9.2`](https://github.com/seanthimons/boosterpak/compare/v0.9.1...v0.9.2)

## v0.9.1 (2026-08-31)

#### Bug fixes

- repair missing package dependencies before snapshot (#15)
  ([a990a9a](https://github.com/seanthimons/boosterpak/tree/a990a9a20ac11c885566b4c9a7f46f3020476198))

#### Docs

- update NEWS.md for v0.9.1 \[skip ci\]
  ([e23540d](https://github.com/seanthimons/boosterpak/tree/e23540dd4d323f1c138835ff82d1cbe64fa5ea96))
- fix clone restore flowchart
  ([5af1807](https://github.com/seanthimons/boosterpak/tree/5af18073c30db89a4e8b01a1fe48f26ae7d15c06))

#### Other changes

- set version to 0.9.1 \[skip ci\]
  ([f687769](https://github.com/seanthimons/boosterpak/tree/f6877699ac0475d2889f7e64901acb07bb761b32))

Full set of changes:
[`v0.9.0...v0.9.1`](https://github.com/seanthimons/boosterpak/compare/v0.9.0...v0.9.1)

## v0.9.0 (2026-08-13)

#### Bug fixes

- preserve lockfile packages during sync snapshot
  ([a4f3a6d](https://github.com/seanthimons/boosterpak/tree/a4f3a6d7ba7c5e40913b23dd21495a0743e37604))

#### Docs

- update NEWS.md for v0.9.0 \[skip ci\]
  ([94e7d1f](https://github.com/seanthimons/boosterpak/tree/94e7d1f8162d19868f5914bc0e996ba4bab75f2e))
- update NEWS.md for v0.9.0 \[skip ci\]
  ([5b347fa](https://github.com/seanthimons/boosterpak/tree/5b347fa411e7b84b0063077e96faad17c08420a3))
- explain external renv libraries
  ([933899c](https://github.com/seanthimons/boosterpak/tree/933899c9b3afed1800c73fcfe4716fc6c2c0c073))

#### Other changes

- bump version to 0.9.0 \[skip ci\]
  ([a4a4157](https://github.com/seanthimons/boosterpak/tree/a4a41571c99c8c99bcb9ecb97503bb5a5c0db835))

Full set of changes:
[`v0.8.0...v0.9.0`](https://github.com/seanthimons/boosterpak/compare/v0.8.0...v0.9.0)

## v0.8.0 (2026-08-12)

#### New features

- add safe project deinitialization (#11)
  ([7392407](https://github.com/seanthimons/boosterpak/tree/7392407be0e1851f64176a1a4b407b8de1792b10))

#### Docs

- update NEWS.md for v0.8.0 \[skip ci\]
  ([62db299](https://github.com/seanthimons/boosterpak/tree/62db299bc28608b8da594bf69297c9d8f0c0a47a))

#### Other changes

- bump version to 0.8.0 \[skip ci\]
  ([68f36c6](https://github.com/seanthimons/boosterpak/tree/68f36c6a912fc065722cbe17bd1dd93a40a181a6))

Full set of changes:
[`v0.7.0...v0.8.0`](https://github.com/seanthimons/boosterpak/compare/v0.7.0...v0.8.0)

## v0.7.0 (2026-07-21)

#### Docs

- update NEWS.md for v0.7.0 \[skip ci\]
  ([ab0edef](https://github.com/seanthimons/boosterpak/tree/ab0edef5b4ec75b71962d6ef016313e91e5d2ad3))
- document package internals for CRAN (#10)
  ([c8840f0](https://github.com/seanthimons/boosterpak/tree/c8840f0c6e909a022056ba89538c935b860ba55f))

#### Other changes

- bump version to 0.7.0 \[skip ci\]
  ([23b8c8a](https://github.com/seanthimons/boosterpak/tree/23b8c8add8f9e8151f5c0824390112a7637a85c1))

Full set of changes:
[`v0.6.5...v0.7.0`](https://github.com/seanthimons/boosterpak/compare/v0.6.5...v0.7.0)

## v0.6.5 (2026-07-20)

#### New features

- support active package libraries
  ([a725088](https://github.com/seanthimons/boosterpak/tree/a72508886730c8a4d733bce441bc5d75b1553b58))

#### Bug fixes

- store renv repos override as named vector
  ([9c02aa9](https://github.com/seanthimons/boosterpak/tree/9c02aa98258e73a244818ae5b0e3b155326ee1af))
- harden rescue install policy
  ([1c03470](https://github.com/seanthimons/boosterpak/tree/1c034700e4cfa0f427fa52276bb998979b897e4a))
- emit bare syntactic repo names
  ([ec1f20c](https://github.com/seanthimons/boosterpak/tree/ec1f20c277889c38e4517415929ab7ad71080ab2))
- keep rescue independent of rlang
  ([c41b46f](https://github.com/seanthimons/boosterpak/tree/c41b46f212fb4a2249a685f4e881d98558872b5b))
- upgrade default-like CRAN mirrors
  ([6d1ca0c](https://github.com/seanthimons/boosterpak/tree/6d1ca0c9a23f82a486bb09b5891c0141c67bb172))

#### CI

- align GitHub Actions across R package repos (#7)
  ([b90466d](https://github.com/seanthimons/boosterpak/tree/b90466d3532460e17ff01ef24c559dd5c922d0c2))

#### Docs

- update NEWS.md for v0.6.5 \[skip ci\]
  ([b586d96](https://github.com/seanthimons/boosterpak/tree/b586d9671ffe5fae844c2b809c127c356a902207))

#### Other changes

- bump version to 0.6.5 \[skip ci\]
  ([2cbee1c](https://github.com/seanthimons/boosterpak/tree/2cbee1ce741378cb0b06fe7df263a0fa20fc799d))

Full set of changes:
[`v0.6.4...v0.6.5`](https://github.com/seanthimons/boosterpak/compare/v0.6.4...v0.6.5)

## v0.6.4 (2026-07-10)

#### Other changes

- bump package version to 0.6.4 (#6)
  ([0f442f6](https://github.com/seanthimons/boosterpak/tree/0f442f6f174b509d52d441c954a357c91baa53f6))
- ignore local log files
  ([272140c](https://github.com/seanthimons/boosterpak/tree/272140c7e95077086ff1c53efd12cc2b631a1755))
- ignore local log files
  ([5909307](https://github.com/seanthimons/boosterpak/tree/59093079d0b16b244ae038df578748f88fac3ca8))

Full set of changes:
[`v0.6.3...v0.6.4`](https://github.com/seanthimons/boosterpak/compare/v0.6.3...v0.6.4)

## v0.6.3 (2026-07-10)

#### Bug fixes

- address PR #4 review feedback
  ([8c3c94d](https://github.com/seanthimons/boosterpak/tree/8c3c94d6e81f98b5815ba2eb6ba49a636435f595))

#### Other changes

- bump package version to 0.6.3 (#5)
  ([d7bf912](https://github.com/seanthimons/boosterpak/tree/d7bf9127e9d7f0310da567eff404304fb9659cbd))

Full set of changes:
[`v0.6.2...v0.6.3`](https://github.com/seanthimons/boosterpak/compare/v0.6.2...v0.6.3)

## v0.6.2 (2026-07-10)

#### New features

- add database pack and rescue tooling
  ([4c65285](https://github.com/seanthimons/boosterpak/tree/4c6528543447336ad91bf7d4a3a55bfbcb9d70eb))

#### Other changes

- bump package version to 0.6.2 (#4)
  ([8369f75](https://github.com/seanthimons/boosterpak/tree/8369f75d9d9cf681e0c7a7a7717d3b5bd9178221))

Full set of changes:
[`v0.6.1...v0.6.2`](https://github.com/seanthimons/boosterpak/compare/v0.6.1...v0.6.2)

## v0.6.1 (2026-07-09)

#### New features

- change to scaffold folder building
  ([e4a7868](https://github.com/seanthimons/boosterpak/tree/e4a7868a80f60398620532f5813f706eb784c24d))
- add per-project pack settings via \[settings.packs\] and
  pack_setting()
  ([4c70c95](https://github.com/seanthimons/boosterpak/tree/4c70c958162dc0b55b1d8e9750ee0ccf7a502a9d))
- update default directories in scaffold_analysis function
  ([a13c56b](https://github.com/seanthimons/boosterpak/tree/a13c56b133de957c6336a763e5c7bcc22d60f183))
- slight adjustment to scaffold analysis
  ([9abaede](https://github.com/seanthimons/boosterpak/tree/9abaeded904702281202b2714f0323769487b81b))
- add data/final directory to scaffold_analysis()
  ([6e50284](https://github.com/seanthimons/boosterpak/tree/6e502840bf46da805c2c8bb2eab96d25584ebd96))
- add add_github_pack() to import packs from a GitHub repo
  ([10cbf97](https://github.com/seanthimons/boosterpak/tree/10cbf97d6de071a6eb9970a0705415407a93292d))
- show pack folder locations in list_packs header
  ([ead4a6c](https://github.com/seanthimons/boosterpak/tree/ead4a6c58af0121fa0019c6378ab25031185c997))

#### Bug fixes

- repair generated legacy parallel daemon setting
  ([1ab9655](https://github.com/seanthimons/boosterpak/tree/1ab9655e72de2650d425bbe58ecf04a4a929273c))
- gate approval builds on reviewer association and build the approved
  commit
  ([d745d92](https://github.com/seanthimons/boosterpak/tree/d745d9264d49d993df31544241edb3c97303a70f))
- install pak via renv when hydrate leaves it missing
  ([d4cb412](https://github.com/seanthimons/boosterpak/tree/d4cb412e3d7064c0b28d35844030cffe8bc6ef58))
- fall back to GitHub spec for locally installed boosterpak
  ([6abb198](https://github.com/seanthimons/boosterpak/tree/6abb19871abfae86928abd9bcd2142b7ab256873))
- update diagram
  ([7268b30](https://github.com/seanthimons/boosterpak/tree/7268b30ff6eb1bee5eab35ad8872ce1d9e64d7bc))

#### Refactorings

- derive function catalog from pack sidecars
  ([5201808](https://github.com/seanthimons/boosterpak/tree/52018088dc0bfbc7c5cf7ebc42e385a70620dbfc))

#### CI

- add release workflow for version bumps
  ([88111b3](https://github.com/seanthimons/boosterpak/tree/88111b388b52858a5de9b47238cda9c6ef06e7f2))
- build package on PR approval
  ([79114fa](https://github.com/seanthimons/boosterpak/tree/79114fa500eab7e26f8efd45130a11eebb83d2ca))

#### Docs

- fix 0.5 bootstrap recipe and dedupe restore guidance into one vignette
  ([40f3c4b](https://github.com/seanthimons/boosterpak/tree/40f3c4b03c0f7bd261bbbb1338bc264994e5f8dd))
- add restoring-a-project vignette for new-machine clone restores
  ([13e7b2a](https://github.com/seanthimons/boosterpak/tree/13e7b2a7520c46c043a1e190c6c0eb6c2ff59850))
- add building-a-pack vignette covering pack schema and on_add hook
  rules
  ([cc6d581](https://github.com/seanthimons/boosterpak/tree/cc6d581aba94c1585c0385b4e980255b0a238d4e))
- add add_github_pack to pkgdown reference index
  ([eb086ec](https://github.com/seanthimons/boosterpak/tree/eb086ec6909afe1a60c225d0c6565402fd48ddac))
- fix mermaid diagram rendering in getting-started article
  ([a54ad04](https://github.com/seanthimons/boosterpak/tree/a54ad04689804ddef0fcfdac116dce9cd94e7520))

#### Style

- reformat packs.R with air
  ([a1a121d](https://github.com/seanthimons/boosterpak/tree/a1a121d3f2edd6666c2cae24c3a45057bb6931fa))

#### Other changes

- bump package version to 0.6.1
  ([c703f60](https://github.com/seanthimons/boosterpak/tree/c703f60789e76dd525651acb73cc8c4b79d85aae))
- drop no-op needs input from dependency setup
  ([6528ead](https://github.com/seanthimons/boosterpak/tree/6528eadf419c249cdd9f3afe3b1b1ff7beb914e5))
- gitignore update
  ([26b0afc](https://github.com/seanthimons/boosterpak/tree/26b0afc59aadd7bbff874471980ac3b8eccd7afa))
- remove old planning docs
  ([f94e25b](https://github.com/seanthimons/boosterpak/tree/f94e25bccb2371f93c83cbf7b04770ade73f7928))

Full set of changes:
[`a91fb9d...v0.6.1`](https://github.com/seanthimons/boosterpak/compare/a91fb9d...v0.6.1)
