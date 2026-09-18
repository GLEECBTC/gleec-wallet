# Contribution guide

## 1. Get to know the project

- Read the [README](/README.md) file
- Read the [Code of Conduct](CODE_OF_CONDUCT.md) file
- Read the [Contribution guide](CONTRIBUTION_GUIDE.md) (this file)

## 2. Set up your local environment

- Read project [Setup guide](PROJECT_SETUP.md)

## 3. Find an issue to work on

- Check the issues, assigned to you on this page: <https://github.com/issues/assigned>
- Pay attention to the priority labels, the higher the priority, the more important the issue is

## 4. Create a new branch

- Create a new local branch from the `dev` branch (`main` for hotfixes), name it according to [branch naming conventions](GITFLOW_BRANCHING.md#branch-naming-conventions)

## 5. Work on the issue

- Read the issue description and comments
- Make sure that you understand the issue, requirements, security details, etc.
- Move related issue to the "In progress" column on the project board
- Be sure to follow the project's coding style and best practices
- Commit your changes in small, logical units with [clear and descriptive commit messages](https://cbea.ms/git-commit/)
- Upload your work branch to the remote, even if it's not finished yet. Update it with new commits as you work on the issue

## 6. Before creating or updating a PR (checklist)

- [ ] Sync your work branch with the latest changes from the target branch (`dev` or `main`), resolve merge conflicts if any
- [ ] (Re)read original issue and comments, make sure that changes are solving the issue or adding the feature
- [ ] Run the unit suite locally — `flutter test test_units/main.dart` **with the four GasFree dart-defines** ([TESTING.md](TESTING.md#2-unit-and-widget-tests)). This is the gating CI job; without the defines it hangs rather than fails
- [ ] Run [integration tests](TESTING.md#3-integration--gui-tests) locally
- [ ] Consider adding tests for your changes — see [which suite to run](TESTING.md#8-which-suite-do-i-run)
- [ ] Test your changes manually
  - [ ] Desktop/mobile view
  - [ ] Dark/light mode
  - [ ] Different browsers (for web build): Chrome, Firefox, Safari, Edge, Brave
  - [ ] Different build modes: debug, release, profile
- [ ] Make sure that `flutter analyze` and `dart format` are passing
- [ ] Always use `flutter pub get --enforce-lockfile` in CI or shared environments for security
- [ ] Use `--no-pub` flag with Flutter commands that automatically run pub get

## 7. Create a PR (checklist)

- [ ] Sync your work branch with the latest changes from the target branch (again :), push it to the remote
- [ ] Make sure that you're opening a PR from your work branch to the proper target branch (`dev` or `main`)
- [ ] Provide a clear and concise title for your PR
  - [ ] Avoid using generic titles like "Fix" or "Update"
  - [ ] Avoid using the issue number in the title
  - [ ] Use the imperative mood in the title (e.g. "Fix bug" and not "Fixed bug")
- [ ] Describe the changes you've made and how they address the issue or feature request
  - [ ] Reference any related issues using the appropriate keywords (e.g., "Closes #123" or "Fixes #456")
  - [ ] Provide test instructions if applicable to help QA engineers test your changes
- [ ] Request a code review from one or more maintainers or other contributors
- [ ] Move related issue to the "Review" column on the project board
- [ ] After code review is done, request testing from QA team
- [ ] Move related issue to the "Testing" column on the project board
- [ ] When QA team approves the changes, merge the PR, move related issue to the "Done" column on the project board

## 8. Maintain your PR

- Once your PR is created, you should maintain it until it's merged
- Check the PR on daily basis for comments, changes requests, questions, etc.
- Address any comments or questions from the code review, or from QA testing
- Make sure that your PR is up to date with the target branch (`dev` or `main`), resolve merge conflicts proactively
- After merging, delete your work branch

## 9. 🎉 Celebrate

- Congratulations! You've just contributed to the project!
- Thank you for your time and effort!
