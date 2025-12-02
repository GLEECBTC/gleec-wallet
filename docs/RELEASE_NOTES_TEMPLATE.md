# Gleec Wallet Release Notes Template

**Tags:** release-notes, changelog, documentation, versioning  
**Application:** Gleec Wallet  
**Platform:** Flutter (Web, Desktop, Mobile)  
**Created:** 2025-05-19
**Updated:** 2025-05-19
**Version:** 1.0

---

## Purpose/Description

This template helps create structured, professional release notes for Gleec Wallet from raw changelog data and commit histories. It organizes development information into a user-friendly format suitable for publishing to users, developers, and stakeholders.

---

## Input Variables

- **{VERSION_NUMBER}:** The version being released (e.g., "1.0.0")
- **{PREVIOUS_RELEASE_NOTES}:** Example of previous release notes to match style and format
- **{CHANGELOG_CONTENT}:** Raw changelog entries or commit messages to be organized
- **{COMMITS_WITH_AUTHORS}:** List of commits with author information for attribution
- **{REFERENCE_VERSION}:** A reference version with particularly good release notes format (e.g., "v0.9.0")

---

## Expected Output Format

The output will be structured markdown-formatted release notes with:

1. **Introduction highlighting significant changes**
2. **New Features section** with attribution and PR links
3. **UI/UX Improvements section** with attribution and PR links
4. **Performance Enhancements section** with attribution and PR links
5. **Bug Fixes section** with attribution and PR links
6. **Security Updates section** (if applicable)
7. **Platform-specific Changes section** (Web/Desktop/Mobile)
8. **Breaking Changes section** (if any)
9. **Link to full changelog**

Headers, expandable sections, and bullet points should be used for readability.

---

## Success Criteria/Metrics

- All significant changes are included and properly categorized
- Changes are described clearly and concisely
- Proper attribution is given to contributors
- Format matches previous release notes style
- Important changes are highlighted prominently
- Technical details are present but not overwhelming
- Platform-specific changes are clearly indicated

---

## Prompt Content

I want to write comprehensive release notes for Gleec Wallet **{VERSION_NUMBER}**.

For reference, here are the previous release notes to match their structure and style:

**{PREVIOUS_RELEASE_NOTES}**

Below is the changelog for Gleec Wallet **{VERSION_NUMBER}**. Please help me organize and format this information into proper release notes. Not everything from the changelog needs to be included - focus on significant features, enhancements, fixes, and breaking changes similar to how previous release notes were structured:

**{CHANGELOG_CONTENT}**

Here are the commits with authors to help you properly attribute changes:

**{COMMITS_WITH_AUTHORS}**

Please create release notes with the following sections:

1. A brief introduction highlighting the most significant changes
2. New Features (with PR links and authors)
3. UI/UX Improvements (with PR links and authors)
4. Performance Enhancements (with PR links and authors)
5. Bug Fixes (with PR links and authors)
6. Security Updates (if applicable)
7. Platform-specific Changes (Web/Desktop/Mobile)
8. Breaking Changes (if any)
9. Full Changelog link

Structure the release notes similarly to Gleec Wallet **{REFERENCE_VERSION}** format, but you can take inspiration from other previous releases as well. Use expandable details sections for longer lists where appropriate. Make the notes informative but concise, highlighting the most important changes first.

For multiplatform changes, please indicate which platforms (Web, Windows, macOS, Linux, Android, iOS) are affected by each change.

If any information is missing or unclear, please ask before completing the release notes.

---

## Example Release Notes Structure

## Gleec Wallet v1.0.0

We are excited to announce the release of Gleec Wallet v1.0.0, which includes [brief summary of major improvements].

## 🚀 New Features

- **Improved Trading Interface**: Enhanced the trading experience with a more intuitive interface and real-time price updates. ([@username], #PRnumber)
- **Multi-coin Support**: Added support for X new coins including [list major coins]. ([@username], #PRnumber)

<details>
<summary>More features...</summary>

- Additional feature 1 ([@username], #PRnumber)
- Additional feature 2 ([@username], #PRnumber)
</details>

## 🎨 UI/UX Improvements

- **Dark Mode**: Implemented a new dark mode theme across all platforms. ([@username], #PRnumber)
- **Responsive Design**: Improved layout on mobile devices. ([@username], #PRnumber)

## ⚡ Performance Enhancements

- **Faster Loading Times**: Reduced initial app loading time by X%. ([@username], #PRnumber)
- **Memory Optimization**: Decreased memory usage during trading operations. ([@username], #PRnumber)

## 🐛 Bug Fixes

- Fixed issue with transaction history not displaying properly on iOS. ([@username], #PRnumber)
- Resolved connectivity problems when using VPN. ([@username], #PRnumber)

<details>
<summary>More bug fixes...</summary>

- Additional bug fix 1 ([@username], #PRnumber)
- Additional bug fix 2 ([@username], #PRnumber)
</details>

## 🔒 Security Updates

- Enhanced wallet encryption methods. ([@username], #PRnumber)
- Improved protection against potential security vulnerabilities. ([@username], #PRnumber)

## 💻 Platform-specific Changes

### Web

- Optimized for the latest Chrome and Firefox versions. ([@username], #PRnumber)

### Desktop (Windows, macOS, Linux)

- Improved native integration with system notifications. ([@username], #PRnumber)

### Mobile (Android, iOS)

- Enhanced biometric authentication support. ([@username], #PRnumber)

## ⚠️ Breaking Changes

- Changed configuration format for custom networks. See [migration guide](#) for details. ([@username], #PRnumber)

## 📚 Documentation

- Updated [user guide](#) with new features and workflows.
- Added detailed [API documentation](#) for developers.

---

**Full Changelog**: [v0.9.0...v1.0.0](https://github.com/GLEECBTC/gleec-wallet/compare/v0.9.0...v1.0.0)

---

## Version History

- **1.0 (2025-05-19):** Initial version, adapted from Gleec Wallet release notes template
