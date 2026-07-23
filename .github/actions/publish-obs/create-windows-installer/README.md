# create-windows-installer

The create-windows-installer action creates and code signs an NSIS-based installation program for Windows platforms. It also strips and separates all program database (`.pdb`) files and also produces a new compressed archive of the build.

## Documentation

### Inputs

| Input | Description | Default |
|:-----:|-------------|---------|
| `path` | The path to a compressed archive containing an OBS Studio build. | `REQUIRED` |
| `architecture` | The build architecture to generate an NSIS-based installation program for. | `REQUIRED` |
| `version` | The version string to generate an NSIS-based installation program for. | `REQUIRED` |

### Outputs

| Output | Description |
|:------:|-------------|
| `installer-path` | The path to the generated NSIS-based installation program. |
| `pdb-path` | The path to the generated compressed archive of the stripped program database files. |
| `archive-path` | The path to the generated compressed archive of the OBS Studio build. |

## Common Usage

The action requires Windows code signing credentials to be set up on the GitHub Actions runner and thus should be used in conjunction with the `codesign-obs/setup-windows` action.

```yaml
      - name: Set Up Code Signing
        uses: ./.github/actions/codesign-obs/setup-windows
        with:
          gcp-identity-provider: ${{ secrets.gcp-identity-string }}
          gcp-account-name: ${{ secrets.gcp-account-name }}

      - name: Create Windows Installer
        id: installer
        uses: ./.github/actions/publish-obs/create-windows-installer
        with:
          path: ${{ format('{0}/builds', runner.temp) }}
```

## Notes

> [!IMPORTANT]
> The action requires a Windows GitHub Actions runner.

* Running the action with the  `arm64` architecture is unsupported because the creation script depends on a custom DLL with NSIS plugins that is not available for any architectures but `x64` at the moment.
* The compressed archive of the OBS Studio build to generate an installation program for needs to be download separately.
* The action will _not_ code sign the provided build, it will only code sign the installation program.

## Developer Notes

The action uses https://github.com/obsproject/bouf to generate the installation program and archives. BOUF and its dependencies are automatically installed on the GitHub Actions runner by the action.
