

# boosterpak NEWS

## v0.7.0 (2026-07-21)

#### Docs

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
