# Releasing porydaw

Releases are cut from `main` by pushing a version tag. CI builds and publishes
the release artifacts (`.github/workflows/release.yml`).

## Steps

1. **Finalize `CHANGELOG.md`.** Retitle the `## [Unreleased]` section to
   `## [X.Y.Z] - YYYY-MM-DD`, add a fresh empty `## [Unreleased]` section above
   it ("Nothing, yet."), and update the link references at the bottom of the
   file:

   ```markdown
   [Unreleased]: https://github.com/huderlem/porydaw/compare/X.Y.Z...HEAD
   [X.Y.Z]: https://github.com/huderlem/porydaw/releases/tag/X.Y.Z
   ```

2. **Bump the version** in `CMakeLists.txt`:

   ```cmake
   project(porydaw VERSION X.Y.Z LANGUAGES C CXX)
   ```

   This is the single source of truth: it flows into the compiled binary
   (`PORYDAW_VERSION`, shown by `Help > About porydaw` and `porydaw --version`)
   and the macOS bundle metadata. The release workflow fails if the tag does
   not match it.

3. **Commit and push** those changes to `main`.

4. **Tag and push the tag** (bare version, no `v` prefix — matching porymap):

   ```sh
   git tag X.Y.Z
   git push --tags
   ```

5. CI then:
   - verifies the tag matches the CMake project version,
   - creates the GitHub release with the tag's `CHANGELOG.md` section as the
     release notes (`tools/extract_changelog.sh` — the workflow fails if the
     changelog has no entry for the tag),
   - builds and attaches self-contained artifacts:
     - `porydaw-linux.zip` — AppImage (bundled Qt),
     - `porydaw-macos-arm64.zip` / `porydaw-macos-x86_64.zip` — `.dmg` via
       `macdeployqt`.

6. **Build and upload the Windows artifact manually.** The Windows build is
   statically linked against the local static Qt kit (CI has no static Qt, so
   this stays a local step). Build it, zip `porydaw.exe` together with
   `RELEASE-README.txt` (renamed `README.txt`) as `porydaw-windows.zip`, and
   attach it to the release via the GitHub UI or:

   ```sh
   gh release upload X.Y.Z porydaw-windows.zip
   ```

   Any other locally built bundles can be added the same way.
