# Contribution Guidelines

Thanks for your interest in contributing to the Transmuter system! Transmuter is a community built protocol and anyone is welcome to improve it.

If you need to get in contact with the repository maintainers, please reach out in the [#developers channel](https://discord.gg/HcRB8QMeKU) of Angle Discord Server.

## Types of Contributing

There are many ways to contribute, but here are a few if you want a place to start:

1. **Opening an issue.** Before opening an issue, please check that there is not an issue already open. If there is, feel free to comment more details, explanations, or examples within the open issue rather than duplicating it. Suggesting changes to the open development process are within the bounds of opening issues. We are always open to feedback and receptive to suggestions!
2. **Resolving an issue.** You can resolve an issue either by showing that it is not an issue or by fixing the issue with code changes, additional tests, etc. Any pull request fixing an issue should reference that issue.
3. **Reviewing open PRs.** You can provide comments, standards guidance, naming suggestions, gas optimizations, or ideas for alternative designs on any open pull request.

## Opening an Issue

When opening an [issue](https://github.com/AngleProtocol/angle-transmuter/issues/new/choose), please title it with a concise problem statement and check that a similar request is not already open or in progress. Not all issues may be deemed worth resolving, so please follow through with responding to any questions or comments that others may have regarding the issue.

## Opening a Pull Request

All pull requests should be opened against the `main` branch. In the pull request, please reference the issue you are fixing.

Pull requests can be reviewed by community members, but to be merged they will need approval from the repository maintainers. Please understand it will take time to receive a response, although the maintainers will aim to respond and comment as soon as possible.

**For larger, more substantial changes to the code, it is best to open an issue and start a discussion with the maintainers to align on the change before spending time on the development.**

Finally, before opening a pull request please do the following:

- Run the Foundry tests with `yarn test`
- Document any new functions, structs, or interfaces following the natspec standard.
- Add tests! For smaller contributions, they should be tested with unit tests, and fuzz tests where possible. For bigger contributions, they should be tested with invariant tests where possible.

## Standards

All contributions must follow the below standards. Maintainers will close out PRs that do not adhere to these standards.

1. All contracts should be formatted with the prettier used in the default vscode config.
2. These contracts follow the [solidity style guide](https://docs.soliditylang.org/en/v0.8.19/style-guide.html) with one minor exception of using the `\_prependUnderscore` style naming for internal contract functions, internal top-level parameters, and function parameters with naming collisions.
3. All external facing contracts should inherit from interfaces, which specify and document its functions with natspec.
4. Picking up stale issues by other authors is fine! Please just communicate with them ahead of time and it is best practice to include co-authors in any commits.
5. Squash commits where possible to make reviews clean and efficient. PRs that are merged to main will be squashed into 1 commit.

## Code of Conduct

Above all else, please be respectful of the people behind the code. Any kind of aggressive or disrespectful comments, issues, and language will be removed.

Issues and PRs that are obviously spam and unhelpful to the development process or unrelated to the core code will also be closed.
