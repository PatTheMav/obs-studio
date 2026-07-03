# OBS Studio GitHub Actions Architecture

OBS Studio uses GitHub Actions to handle the following GitHub events:

* `pull_request` - any pull request targeting the main branch.
* `push` - any indirect push to the main branch (usually a merged pull request or a tagged version).
* `schedule` - automatic nightly builds and GitHub Actions maintenance tasks.
* `dispatch` - manual trigger of workflows to fix possible issues caused as part of automatic workflow runs.
* `publish` - any semantic version release created on GitHub

These events are handled by dedicated workflows, which themselves trigger other independent workflows that implement common functionality (e.g. building OBS Studio) to avoid code duplication between workflows.

## Workflow Dependency Chart

The following diagram visualizes the relationship between the different workflows:
```
 ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
 │ PULL-REQUEST │    │     PUSH     │    │   DISPATCH   │    │   SCHEDULE   │    │   PUBLISH    │
 └──────┬───────┘    └──────┬───────┘    └──────┬───────┘    └──────┬───────┘    └──────┬───────┘
        │                   │                   │                   │                   │
        │                   │                   │                   │                   │
┌───────▼────────┐  ┌───────▼────────┐  ┌───────▼────────┐  ┌───────▼────────┐  ┌───────▼────────┐
│  pr-pull.yaml  │  │   push.yaml    │  │  dispatch.yaml │  │ schedule.yaml  │  │  publish.yaml  │
└───┬───┬────────┘  └┬─────────┬───┬─┘  └──┬─────────────┘  └─┬───┬────────┬─┘  └───────┬────────┘
    │   │            │         │   │       │                  │   │        │            │
    │   │            │         │   │       │    ┌─────────────┘   │        │            │
    │   └────────────│───────┐ │   │       │    │                 │        └─┐          │
┌───▼────────────────▼─┐   ┌─▼─▼───┴───────┴────▼─┐ ┌─────────────▼────────┐ │          │
│  lint-project.yaml   │   │  build-project.yaml  │ │ analyze-project.yaml │ │          │
└──────────────────────┘   └───────┬───────┬──────┘ └──────────────────────┘ │          │
                                   │       │        ┌──────────────────────┐ │          │
                                   └────────────────►  sign-windows.yaml   │ │          │
                                           │        └──────────────────────┘ │          │
                                           │                                 │          │
                                           │                              ┌──▼──────────▼────────┐
                                           └──────────────────────────────►  publish-steam.yaml  │
                                                                          └──────────────────────┘
```

## Detailed Workflow Descriptions

### pr-pull.yaml

|  GitHub Event  |           Event Types           | Automatic  | # Jobs | # Actions |
|----------------|---------------------------------|:----------:|:------:|:---------:|
| `pull_request` | `opened, synchronize, reopened` |     ✅     |    3   |     3     |

|          3rd-Party Actions          |                    Hash                    |
|-------------------------------------|: ---------------------------------------- :|
| https://github.com/actions/checkout | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |


This workflow runs for every new pull request (depending on repository settings) targeting the `main` or `master` branch, except if the changes are limited to markdown files only. If the pull request is reopened or "synchronized" (usually triggered by a force-push to the source reference), the workflow is triggered as well.

When triggered, the workflow will itself use the [`lint-project`]() and [`build-project`]() workflows to have the linters and compilers run in parallel. If any of them has any failures, the entire integration check will be considered a failure.

> [!IMPORTANT]
> The [`build-project`]() workflow needs to inherit repository secrets to be able to use code signing on macOS.

Additionally, if any documentation files have been changed by the pull request, the documentation pages are built to check that any changes to `sphinx` files do not break documentation generation.

#### Order Of Events

1. `pull_request` event
2. `pr-pull` workflow runs
    * `lint-project` is triggered
    * `build-project` is triggered
    * `update-documentation` job runs

### push.yaml

|  GitHub Event  |  Tags  | Automatic  | # Jobs | # Actions |
|----------------|--------|:----------:|:------:|:---------:|
|     `push`     |  `*`   |     ✅     |    6   |     3     |

| 3rd-Party Actions                             |                    Hash                    |
|-----------------------------------------------|: ---------------------------------------- :|
| https://github.com/actions/checkout           | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| https://github.com/actions/download-artifact  | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` |
| https://github.com/cloudflare/wrangler-action | `ebbaa1584979971c8614a24965b4405ff95890e0` |
| [.github/workflows/sign-windows.yaml](https://github.com/obsproject/obs-studio/blob/master/.github/workflows/sign-windows.yaml) | `ac19ea663375cd02997be92b7d8ff6dd89a511ad` |

This workflow runs for any direct push to a `main` or `master` branch and any push to a release branch (e.g. `release/32.0.0`). Just like the `pull-request` workflow, pushes that contain just changes to markdown files are ignored, the [`lint-project`]() and [`build-project`]() workflows are used to lint the code changes and build the project with the latest commit of the push, and documentation is generated as well.

> [!IMPORTANT]
> The [`build-project`]() workflow needs to inherit repository secrets to be able to use code signing on macOS.

For pushed tags, additional jobs are executed:

The built documentation is deployed to Cloudflare pages, the Windows build artifacts generated by `build-project` are used to code sign the game capture functionality, before creating a GitHub release with those artifacts.

> [!IMPORTANT]
> The [`sign-windows`]() workflow needs to inherit repository secrets to be able to use code signing on macOS. It also requires a repository token with the following permissions:
>
> |    Permission    |   Type    | Comment                                                         |
> |:----------------:|:---------:|-----------------------------------------------------------------|
> |    `contents`    |  `read`   | Necessary to list commits and other repository data.            |
> |    `id-token`    |  `write`  | Necessary fetch an OpenID Connect (OIDC) token.                 |
> |  `attestations`  |  `write`  | Necessary to generate an attestation for the code signed build. |


The release generated by the workflow is always set as `draft` to allow project maintainers to make additions or changes to the release, particularly in the event of any errors that might have occurred during the entire workflow run and that might only affect a single platform (but not all).

#### Order Of Events

1. `push` event.
2. `push` workflow runs.
3. First layer:
    * `lint-project` is triggered.
    * `build-project` is triggered.
    * `update-documentation` job runs.
4. Second layer:
    * `deploy-documentation` runs if `update-documentation` is successful.
    * `sign-windows-build` runs if `build-project` is successful.
5. Third layer:
    * `create-release` runs if `sign-windows-build` is succesul.

> [!NOTE]
> The `create-release` job has an indirect dependency on `build-project`, which is guarded by `sign-windows-build`.

#### Pinned hash of `sign-windows.yaml`

The hash for the [](`sign-windows.yaml`) workflow dispatch is pinned to a specific commit. This allows the code signing implementation to guard access to credentials to this specific variant of the workflow. The jobs within that workflow are also designed to check out (and only act) on the version of the repository at this commit.

The detailed description for the workflow has more information on the repercussions and requirements introduced by this design.

### dispatch.yaml

|  GitHub Event  |                             Inputs                              | Automatic  | # Jobs | # Actions |
|----------------|-----------------------------------------------------------------|:----------:|:------:|:---------:|
|   `dispatch`   | `job, ref, customAsset[Windows|MacOSApple|MacOSIntel], channel` |     ❌     |    7   |     3     |

| 3rd-Party Actions                              |                    Hash                    |
|------------------------------------------------|: ---------------------------------------- :|
| https://github.com/actions/checkout            | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| https://github.com/obsproject/obs-crowdin-sync | `4b488c7ced03aa109d9f12529bd91c26c54b3e89` |
| https://github.com/cloudflare/wrangler-action  | `ebbaa1584979971c8614a24965b4405ff95890e0` |

This workflow needs to be dispatched manually by project members. Unlike other workflows in the project, this one requires a specific use case to be selected before dispatching, which effectively "selects" the kind of jobs that are actually run.

The available options are:

* `steam` - creates and uploads a new build for OBS Studio's Steam release. This job provides additional inputs:
    * `customAssetWindows` - a URL pointing to a complete OBS Studio package for Windows.
    * `customAssetMacOSApple` - a URL pointing to a complete OBS Studio package for macOS and Apple Silicon SOCs.
    * `customAssetMacOSIntel` - a URL pointing to a complete OBS Studio package for macOS and Intel CPUs.
    * These custom assets replace any automatically downloaded asset of the same name.
    * For more information consult the action's own README file.
* `services` - runs validation on the `services.json` file shipped as part of the `rtmp-services` module of OBS Studio.
* `translations` - downloads language files from Crowdin (this is a legacy job and currently under investigation).
* `documentation` - builds and updates Sphinx-based documentation.
* `patches` - generates update files for the Windows updater. This job provides additional input:
    * `channel` - the OBS update channel to be used for generating Windows update files.

All jobs of the dispatch workflow require the additional input named `ref`, which represents the git reference (commit hash, tag, or branch) that the workflow's jobs will use as their context.

#### Git Reference Requirements For Jobs

**TBD**

### scheduled.yaml

|  GitHub Event  |  Cron Spec   | Automatic  | # Jobs | # Actions |
|----------------|--------------|:----------:|:------:|:---------:|
|   `schedule`   | `17 0 * * *` |     ✅     |    6   |     2     |

| 3rd-Party Actions                              |                    Hash                    |
|------------------------------------------------|: ---------------------------------------- :|
| https://github.com/actions/checkout            | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| https://github.com/obsproject/obs-crowdin-sync | `4b488c7ced03aa109d9f12529bd91c26c54b3e89` |


This workflow takes care of daily maintenance jobs, scheduled to run about 15 minutes past midnight UTC. The maintenance jobs check the state of the project based on the current head of the main branch and include:

* Cleaning stale compilation caches
* Building the project for all supported platforms and populating the compilation caches.
* Run static code analysis.
* Upload any added or changed language files for translation.
* Check availability of streaming services.
* Upload generated nightly builds to Steam.

As the head of the main brach might not have changed in 24 hours, the git references associated with the last 2 runs of the workflow are compared to ensure that the commit hash actually changed before uploading a new build to Steam or uploading new language files.

Availability of streaming services is checked on every nightly run regardless of any changes to the head of the main branch.

#### Order Of Events

1. `schedule` event.
2. `scheduled` workflow runs.
3. First layer:
    * `services-availability` job runs.
    * `cache-cleanup` job runs.
    * `upload-language-files` job runs.
4. Second layer:
    * `build-project` is triggered.
    * `analyze-project` is triggered.
5. Third layer:
    * `steam-upload` job runs

### publish.yaml

|  GitHub Event  |  Event Types   | Automatic  | # Jobs | # Actions |
|----------------|--------------|:----------:|:------:|:---------:|
|   `release`    | `published`  |     ✅     |    6   |     3     |

| 3rd-Party Actions                                 |                    Hash                    |
|---------------------------------------------------|: ---------------------------------------- :|
| https://github.com/actions/checkout               | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| https://github.com/actions/upload-artifact        | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| https://github.com/flatpak/flatpak-github-actions | `401fe28a8384095fc1531b9d320b292f0ee45adb` |

| Docker Containers | Hash |
|-------------------|:----:|
|[flathub-infra/flatpak-github-actions](https://github.com/flathub-infra/actions-images/pkgs/container/flatpak-github-actions) | `364e5ede018e821ba430849690649ac7ec43d082c29ba4be3d357c517262ea1f`|

This workflow runs when a GitHub release of OBS Studio is published based on a tag either on the main branch or release branch. This enables automatic generation of patch files or publishing of builds to app stores with a release version of the application.

The workflow will run additional checks on the tag to ensure that it does represent a semantic version string (so arbitrary tag names are ignored). If the tag passes tests, the workflow will:

* Will do a full build of the project for Flatpak, validate the build and publish it to Flathub.
* Upload the builds attached to the GitHub release to Steam.
* Generate patch files for the Windows updater.
* Create Appcast and delta update files for Sparkle (the updater framework used in macOS builds).
* Merge and upload appcast files.

The generated files are then attached as workflow artifacts and can be used by project members to upload to the respective systems that require them.

#### Order Of Events

1. `release` event.
2. `publish` workflow runs.
3. First layer:
    * `check-tag` job runs.
4. Second layer:
    * `flatpak-publish` job runs.
    * `steam-upload` job runs.
    * `windows-patches` job runs.
    * `create-appcast` job runs.
5. Third layer:
    * `merge-appcasts` job runs.

### build-project.yaml

|    GitHub Event   |  Automatic  | # Jobs | # Actions |
|-------------------|:----------:|:------:|:---------:|
|  `workflow_call`  |     ❌     |    5   |     4     |

| 3rd-Party Actions                                 |                    Hash                    |
|---------------------------------------------------|: ---------------------------------------- :|
| https://github.com/actions/checkout               | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| https://github.com/actions/upload-artifact        | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| https://github.com/actions/cache                  | `27d5ce7f107fe9357f9df03efb73ab90386fccae` |
| https://github.com/flatpak/flatpak-github-actions | `401fe28a8384095fc1531b9d320b292f0ee45adb` |

| Docker Containers | Hash |
|-------------------|:----:|
|[flathub-infra/flatpak-github-actions](https://github.com/flathub-infra/actions-images/pkgs/container/flatpak-github-actions) | `364e5ede018e821ba430849690649ac7ec43d082c29ba4be3d357c517262ea1f`|

This workflow is the "work horse" of OBS Studio's GitHub Actions setup. It implements 4 parallel jobs that compile the application for Windows (`x64` and `ARM64`), macOS (`ARM64` and `x86_64`), Ubuntu (`x86_64`), and Flatpak (`x86_64`). The workflow is called by "parent" workflows that handle specific GitHub events and thus reacts to the current event it is called with:

* Default build settings use optimisations and embedded debug information (`RelWithDebInfo` in CMake parlance).
    * Note that both Windows (`.pdb`) as well as macOS (`.dSYM`) use separate debug information for optimised builds by default.
* For `pull_request` events, the project is built with default build settings and no artifacts are generated by default. The `Seeking Testers` tag has to be added as a label to a pull request to enable artifact generation.
* For `push`  events, the project is built with default build settings, except for pushed tags, which switches to full optimisations (`Release`).
    * Package generation is enabled as well, creating `.zip` archives for Windows, `.dmg` disk images for macOS, and `.deb` packages for Ubuntu.
    * On macOS code signing will be enabled, with notarization being limited to pushed tags.
* For `workflow_dispatch` events, the project is built with default build settings and code signing enabled on macOS.
* For `schedule` events, the project is built with default build settings and code signing enabled on macOS. Generated builds will be packaged just like `push` events.

To speed up iterative builds of the project, compilation caches are used on macOS-based and Ubuntu-based runners. The caches are based on the current head of the main branch and are refreshed every night. This potentially reduces the scale of cache misses to changes introduced by a pull request or push and should still speed up compilation of unchanged or otherwise unaffected files.

> [!NOTE]
> Compilation caching uses `ccache` on Ubuntu and the built-in Xcode compilation cache on macOS (based on LLVM's CAS storage).

Every build run produces at the very least a full build of OBS Studio, debug symbols, libraries required for plugin development (Windows and macOS only), as well as a "tarball" of the actual sources used to build the project (Ubuntu only). Ubuntu builds commonly use either the most recent stable distribution version or a tandem of the current and outgoing stable version.

Flatpak builds manage their own compilation cache, as all dependencies are built from scratch for a Flatpak artifact. As those dependencies change at a much slower pace, caching those between builds speeds up Flatpak bundle generation tremendously, but also requires more space on the runners and thus makes it necessary to remove elements from the runner's drive that are not necessary for a Flatpak build. This cleanup includes files related to:

* CodeQL
* Python
* GHCUp
* Android development environment
* .NET development environment
* Swift development environment

#### Order Of Events

1. `workflow_call` event.
2. `build-project` workflow runs.
3. First layer:
    * `check-event` job runs.
    * `macos-build` job runs.
4. Second layer:
    * `ubuntu-build` job runs.
    * `flatpak-build` job runs.
    * `windows-build` job runs.

### lint-project.yaml

|    GitHub Event   |  Automatic  | # Jobs | # Actions |
|-------------------|:----------:|:------:|:---------:|
|  `workflow_call`  |     ❌     |    8   |     1     |

| 3rd-Party Actions                                 |                    Hash                    |
|---------------------------------------------------|: ---------------------------------------- :|
| https://github.com/actions/checkout               | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |

This companion to the `build-project` workflow runs linters depending on the files changed in the GitHub event that triggered the original workflow. Each linter runs individually and failure does not impact any other job in the workflow (this ensures that all changed files are fully linted). The implemented linters include:

|     Linter     |                Git Pathspec                |  Comment            |
|:--------------:|:------------------------------------------:|---------------------|
| `clang-format` | `'*.c' '*.h' '*.cpp' '*.hpp' '*.m' '*.mm'` | Checks formatting.  |
| `swift-format` |                `'*.swift'`                 | Checks formatting.  |
|   `gersemi`    |       `'*.cmake' '*CMakeLists.txt'`        | Checks formatting.  |
|    `zizmor`    |  `'.github/**/*.yaml' '.github/**/*.yml'`  | Checks correctness. |
|    `xmllint`   |         `'frontend/forms/**/*.ui'`         | Checks correctness. |
|     Custom     |  `'build-aux/com.obsproject.Studio.json'`  | Checks correctness. |
|     Custom     |     `'plugins/win-capture/data/*.json'`    | Checks correctness. |
|     Custom     |     `'plugins/rtmp-services/data/*.json'`  | Checks correcntess. |

More information about the specific linters can be found in the `README` file of each linter's GitHub Action.

#### Order Of Events

1. `workflow_call` event.
2. `lint-project` workflow runs.
3. First layer:
    * `clang-format` job runs.
    * `swift-format` job runs.
    * `gersemi` job runs.
    * `zizmor` job runs.
    * `flatpak-validator` job runs.
    * `qt-xml-validator` job runs.
    * `compatibility-validator` job runs.
    * `services-validator` job runs.

### analyze-project.yaml

|    GitHub Event   |  Automatic  | # Jobs | # Actions |
|-------------------|:----------:|:------:|:---------:|
|  `workflow_call`  |     ❌     |    2   |     1     |

| 3rd-Party Actions                    |                    Hash                    |
|--------------------------------------|: ---------------------------------------- :|
| https://github.com/actions/checkout  | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |

This workflow runs static code analysis on Windows (using PVS-Studio) and macOS (using `clang-analyze`) and converts the generated analysis files into a single SARIF file as expected by GitHub for use with CodeQL.

#### Order Of Events

1. `workflow_call` event.
2. `analyze-project` workflow runs.
3. First layer:
    * `windows` job runs.
    * `macos` job runs.

### sign-windows.yaml

|    GitHub Event   |  Automatic  | # Jobs | # Actions |
|-------------------|:----------:|:------:|:---------:|
|  `workflow_call`  |     ❌     |    1   |     3     |

| 3rd-Party Actions                    |                    Hash                    |
|--------------------------------------|: ---------------------------------------- :|
| https://github.com/actions/checkout  | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| https://github.com/actions/upload-artifact        | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| https://github.com/actions/attest | 59d89421af93a897026c735860bf21b6eb4f7b26 |

This workflow is a bit special in the sense that it would be more elegant to be implemented as repository action, but has to be implemented as a workflow for security reasons.

To ensure this workflow finishes successfully, it has to be called with a specific commit hash which is considered a "known good" commit of the repository. Only this commit of the workflow will be able to fetch the credentials necessary to apply code signing.

> [!NOTE]
> This design has repercussions: If any dependency of this workflow or the workflow file itself are changed, there has to be a single new commit that encompasses all these changes and a second commit that updates the _calling_ workflow to use this "pinned" commit when calling the child workflow.
>
> This also requires that the `checkout` action used in this workflow (and all other actions) need to run in the context of this commit hash.

#### Order Of Events

1. `workflow_call` event.
2. `sign-windows` workflow runs.
3. First layer:
    * `create-windows-update` job runs.

## Additional Notes

The current implementation of workflows and actions prefers composition as a design goal. A set of principles was used to decide whether to use a workflow, a "large" action, or a "small" action:

* If a GitHub event is handled, use a workflow.
* If jobs need to run in parallel, but also on different runner operating systems, use a workflow.
* If the jobs are potentially necessary for more than one GitHub event, use workflow calls with a reusable workflow.
* If the jobs can run in parallel and can all run on the same runner operating system, use a "large" repository action with parallel step execution.
* If the action step is potentially necessary for more than one repository action, create a new "small" repository action for just this single job.
* If the step in an action requires a shell script with more than 10 lines, extract into a bespoke script file and call it from the action instead.
    * Always pass action inputs to scripts as environment variables and check their values if user provided (e.g. commit titles, labels, tag names, etc.)

This avoids repetition of code in different workflows and also potentially highlights conceptual or design issues, e.g. when two or more actions do almost the same thing, differentiatied by maybe one or two different inputs.
