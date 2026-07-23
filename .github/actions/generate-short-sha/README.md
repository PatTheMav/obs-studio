# generate-short-sha

The generate-short-sha action creates a shortened SHA variant of the current git SHA.

## Documentation

### Inputs

| Input | Description | Default |
|:-----:|-------------|---------|
| `sha` | The git SHA to generate a shortened SHA variant from. | `github.sha` |
| `working-directory` | The path to a git repository from which the SHA originates. | `github.workspace` |

### Outputs

| Output | Description |
|:------:|-------------|
| `sha` | The shortened SHA variant generated from the input `sha`. |

## Common Usage

The action has a single precondition, mainly that it runs in the context of a valid git checkout which contains the provided git ref identified by the SHA.

```yaml
      - name: Generate Short GitHub SHA
        id: short-sha
        uses: ./.github/actions/generate-short-sha

```

## Notes

This action differs from a simple string operation by actually running `git` to create the shortened SHA variant, which will then be truncated to the shortest variant possible for the git repository.

> [!IMPORTANT]
> If the provided SHA is invalid, the action will fail.

## Developer Notes

As mentioned in the notes, the action uses `git rev-parse --short` to generate the shortened SHA variant, which requires that the input SHA is a valid git ref in the current git repository.
