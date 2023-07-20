OBS CMake code guidelines
=========================

* Use `cmake-format` to have your CMake scripts formatted automatically
* Maximum line-length: 100 characters
* Indentation: 2 spaces (no tabs)
* CMake script is stringly typed, everything is a string - we use this to our advantage:
    * Do not enclose variables in double quotes by default
    * **DO** enclose variables in double quotes if variable contains a `PATH` or `FILEPATH`
    * **DO** encose variables in double quotes if variable is a list (aka semicolon-separated string) used in a function call that takes a single variable
* **Global** variables use upper-snake-case, e.g. `MY_VARIABLE`
* **Internal** variables (defined via `CACHE INTERNAL`) use upper-snake-case with an underscore prefix, e.g. `_MY_INTERNAL_VARIABLE`
* **Directory scope** variables use upper-snake-case when public, lower-snake-case with an underscore prefix if private, e.g. `MY_VAR` and `_my_var` respectively
* **Function scope** variables use lower-snake-case, e.g. `my_variable`
* Short function calls that fit into a single line should stay so, e.g.:

```
    set(MY_VARIABLE "my_value")
    list(APPEND my_list value)
```

* Longer function calls should wrap, use keyword arguments as a semantic help, e.g.:

```
    set_target_properties(
      target
      PROPERTIES A_PROPERTY "a value"
                 ANOTHER_PROPERTY "another_value")

    add_custom_command(
      TARGET target
      POST_BUILD
      COMMAND some command "a long variable"
              "another long variable"
      COMMENT "some comment")

    set_source_file_properties(
      file_path PROPERTIES SOME_PROPERTY "some value"
                           ANOTHER_PROPERTY "another value")

    list(
      APPEND
      my_list
      value
      another_value
      yet_another_value)
```

* When in doubt, let `cmake-format` reformat the file for you
* Macro names use upper-snake-case, e.g. `MY_MACRO(var)`
* Function names use lower-snake-case, e.g. `my_function(var)`
* Macro and function variable names are lower-snake-case, e.g. `my_function(my_variable)`
* Use macros for small pieces of code that are used repeatedly, intended use is _composition_.

**Note:** Macros run within the scope they are called in, their code effectively runs in place of the macro call

* Use functions for larger operations used repeatedly, but also set up a lot of temporary variables.

**Note:** Functions run in their own scope, but inherit copies of variables defined in the parent scope. Use `PARENT_SCOPE` to change the contents of variables defined in the parent scope - use with caution!
