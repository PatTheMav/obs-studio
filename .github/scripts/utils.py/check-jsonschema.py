import os
import sys
import json
from typing import Any

from jsonschema import Draft7Validator
from json_source_map import calculate
from json_source_map.errors import InvalidInputError


def prep(filename: str) -> tuple[str, dict[Any, Any], str, dict[Any, Any]] | None:
    try:
        with open(filename) as json_file:
            json_string = json_file.read()
            json_data = json.loads(json_string)
    except OSError as e:
        print(f'Failed to load file "{filename}": {e}')
        return None

    schema_filename = json_data.get("$schema")
    if not schema_filename:
        print("File has no schema:", filename)
        return None

    file_path = os.path.split(filename)[0]
    schema_file = os.path.join(file_path, schema_filename)

    try:
        with open(schema_file) as json_file:
            schema = json.load(json_file)
    except OSError as e:
        print(f'Failed to load schema file "{schema_file}": {e}')
        return None

    return (filename, json_data, json_string, schema)


def validate(
    filename: str, json_data: dict[Any, Any], json_string: str, schema: dict[Any, Any]
) -> list[dict[str, Any]]:
    try:
        servicesPaths = calculate(json_string)
    except InvalidInputError as e:
        print("Error with file:", e)
        return []

    cls = Draft7Validator(schema)

    errors = []
    for e in sorted(cls.iter_errors(json_data), key=str):
        print(f'{e}\nIn "{filename}"\n\n')
        errorPath = "/".join(str(v) for v in e.absolute_path)
        errorEntry = servicesPaths["/" + errorPath]
        errors.append(
            {
                "file": filename,
                "start_line": errorEntry.value_start.line + 1,
                "end_line": errorEntry.value_end.line + 1,
                "title": "Validation Error",
                "message": e.message,
                "annotation_level": "failure",
            }
        )

    return errors


def main():
    if len(sys.argv) < 2:
        print("JSON path required.")
        return 1

    errors = []

    for filename in sys.argv[1:]:
        result = prep(filename)

        if result:
            (filename, json_data, json_string, schema) = result

            new_errors = validate(filename, json_data, json_string, schema)

            errors.append(new_errors)

    try:
        with open("validation_errors.json", "w") as outfile:
            json.dump(errors, outfile)
    except OSError as e:
        print(f"Failed to write validation output to file: {e}")
        return 1

    if errors:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
