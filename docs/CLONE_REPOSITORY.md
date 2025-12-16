# Clone repository

There are two options, cloning via HTTPS or via SSH. HTTPS is recommended.

## HTTPS Clone (Recommended)

If using HTTPS, run:

```bash
git clone https://github.com/GLEECBTC/gleec-wallet.git
cd gleec-wallet
git submodule update --init --recursive
```

Alternatively, you can clone with submodules in one command:

```bash
git clone --recurse-submodules https://github.com/GLEECBTC/gleec-wallet.git
```

## SSH Clone

For SSH cloning you need to [setup SSH authentication](https://docs.github.com/en/authentication/connecting-to-github-with-ssh) properly.
Then you should be able to run:

```bash
git clone --recurse-submodules git@github.com:GLEECBTC/gleec-wallet.git
```

Or if you already cloned without submodules:

```bash
git clone git@github.com:GLEECBTC/gleec-wallet.git
cd gleec-wallet
git submodule update --init --recursive
```

## IDE Integration

**Important**: After cloning via IDE, you must initialize the submodules manually:

```bash
cd gleec-wallet
git submodule update --init --recursive
```

## Verifying Submodule Setup

After cloning, verify that the SDK submodule was initialized correctly:

```bash
ls -la sdk/
```

You should see the komodo-defi-sdk-flutter repository contents in the `sdk/` directory.

## Next Steps

After successfully cloning and initializing submodules:

1. Follow the [Project Setup](PROJECT_SETUP.md) guide for environment configuration
2. Review [SDK Submodule Management](SDK_SUBMODULE_MANAGEMENT.md) for working with the SDK
