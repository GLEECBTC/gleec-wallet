import 'dart:math';

/// Wallets held back from [getFundedWif] for the DEX counterparty.
///
/// The taker test buys MARTY, so somebody other than the app has to be selling
/// it: a node on the same seed is the app's own order, which the self-trade
/// guard rejects. `tool/dex_counterparty.dart` runs a second KDF on one of
/// these wallets, and reserving them here is what keeps the app from drawing
/// the counterparty's wallet and trading with itself again by accident.
const int reservedCounterpartyWallets = 4;

/// A funded wallet for the app under test, drawn at random.
///
/// Never returns a wallet reserved for a counterparty.
String getFundedWif() {
  final addresses = _selectableAddresses;
  final address = addresses[Random().nextInt(addresses.length)];

  return _fileJson[address]['private_key'] as String;
}

/// The wallet a counterparty in [slot] trades from, counted from the end.
///
/// Fixed rather than random: two processes drawing at random from the same
/// thousand wallets collide eventually, and a collision here looks exactly
/// like the self-trade the counterparty exists to avoid.
String getCounterpartyWif(int slot) {
  if (slot < 0 || slot >= reservedCounterpartyWallets) {
    throw ArgumentError.value(
      slot,
      'slot',
      'must be below $reservedCounterpartyWallets',
    );
  }
  final addresses = _fileJson.keys.toList();

  return _fileJson[addresses[addresses.length - 1 - slot]]['private_key']
      as String;
}

String getRandomAddress() {
  final addresses = _selectableAddresses;

  return addresses[Random().nextInt(addresses.length)];
}

List<String> get _selectableAddresses {
  final addresses = _fileJson.keys.toList();

  return addresses.sublist(0, addresses.length - reservedCounterpartyWallets);
}

final _fileJson = <String, dynamic>{
  'RPDPE1XqGuHXSJn9q6VAaGDoRVMEwAYjT3': {
    'private_key': 'UtNh1tePcAqtPppcTMUdW8qSw9tS9izvCcauMCB4UxTevzCqSFkj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQCyFA4cAyjpfzcCGnxNxC4YTQsRDVPzec': {
    'private_key': 'UwAEQTqbN5TQQhi33harSXp5K13ukaXVoyeTvDapoAymZjEvkXBu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKXzCCaT5ukqnyJBKTr9KyEpCBHR8itEFd': {
    'private_key': 'Uvc4wDXD2iLm6tP7FuyvFyAxCHro9R8v3qmkcAJdQJStenScnVpx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RD8WeYCaBQSx9e6mH5hX51uZ5FxNyirawj': {
    'private_key': 'Uvrfi6PxwKKD4ZupfAwtKGTpMhjBC2CSAGQ1BAH5xtWiRo9Jb9h5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVmiEScJqWchKNEq4noaznCVeMg4VRhDVB': {
    'private_key': 'Uu6WZimEEctFHBum1uW3cXokjkSXU7Z6tgcsUWaaJFnD13jQBKXi',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPBaCKmtaeg87hJaP4ebrQmVZBeebpPGip': {
    'private_key': 'UpgHNGM7GNZoMCwFaz9ZXCgqfg6ZZBiiz5iMGCtXibxu9Wtvzz5R',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RK5fL2NrKqFsNNv5eAtBPsHwUB7nS1pJLe': {
    'private_key': 'Usz25M5Aj1FTqzE4JMiGdkCsAop95oF3ei4fkn5oAGdePhrf9oRa',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYEDgkmmh1cRrhuTnYvKjJXasFNh2YQ8Mv': {
    'private_key': 'UrLmBJDRo9XJ6JMPeRzT6xwKEkqwevGpaCyhjnXwtM9nYbvx8fHh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDJarCHAWcCu3i81Jf3UVAH47LZMzMEgZW': {
    'private_key': 'UsPkKCMrSCi4Hky5ZCkFVfmiZgJDD79q1PhiYaAEuLB7x7ntMRXv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSicNrr9yhCeXWShcwun5TAs5NbWHm8rBo': {
    'private_key': 'Ux7ymirpeLDKEJdxgYmCFt11J4k3tzu7WvKx1BnqBPhtwgwbk4V9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9gHR7C3CDTKQfXtvJcRkf2mU1DhS3Ydsb': {
    'private_key': 'Utkx8HrmMB9pUhENHuKhnGej2cJ8qtW8K2vR5eWp14tHpH2gDwQ6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQaFegkCdRUpVT74GAeNsVuqygTC2cxoRH': {
    'private_key': 'UqG98bdSFXhPhF41fJn7cknEEYsvAzJwwrw6f8qtiN6AAdatvB1W',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLMqj85UKRJnmxGBYVJ7tmCputtzXjkm6H': {
    'private_key': 'UvWPoFgZFyqzz3khtNZbwDcj5KPasDQp4XawTiSya95F4ibY7z78',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBwGmCih6tqrLB2FeHc5MXQZmeC9BnJ76L': {
    'private_key': 'Ur4vnvbDkdZZWUXtXrYXXXR6YCvHN3T36hciZp65h5cjNp3gTsD9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBmUXpsdXcrzDkJbbPjSWMCSmLixWPp7sb': {
    'private_key': 'UsCUZEv1paEmxxr6MzV4R9qo6qLNwAWFozMVUA8pebVz16D1xprZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RH5q6iBqqBUwi3PntQtZdfzUT1gQMcQomN': {
    'private_key': 'Ur71NnLa5dvm2gaByer4v4fw6pkVDGDx6bCtj4ew1HVcV5xaZACp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFPJHDoS7MTPH3c7gjTjkDsMuevsiwFNDW': {
    'private_key': 'UsoLh8jCxAzHby22JwdS35hGFoSLGaBnkMfDfSbVF2veswPg3EeJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRA28xfJK4m7G264iskvVuG5ZNRFie4Wtc': {
    'private_key': 'Ur832LZ6rYXAE5bzB73TFif9AYf2KLrh6hkAnhpe1sScuQzGRZAh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9gGgXKxmGwrovF9jAy1groQL2euVBqKie': {
    'private_key': 'UqVYjX6YzE2zvfmPo2m9mX2Leb5ZnMz74QC78Jwt9Z1qhRsrNVih',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBGQbv78oHLXz7oAGu2UoS5SDMX73bdWhv': {
    'private_key': 'UwzibAPUanCDhLnf13FphpksLWDR9oL9cCeNAeHtz2B1LV1V5zK2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWnMitMKTdKQKwYjvQpCueckVgW51ZgCv1': {
    'private_key': 'UqoWNQE4m31vEhyAjtXH9mQNvU2Qbb8E9LQ4jTR3eo6EAp9kaSzL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX7Vyr83G1XV8napKp4U22qYNm2pRcdh75': {
    'private_key': 'UxFyBFsQ87BUXPDKiCWWXCBCxUUoPHxbssfgbHC7ZtzA7mHctiRm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWyPsb5UUzh9W81472wSDLPe6pRcFysG6e': {
    'private_key': 'UwofUdJDHQCzL9K11Utkdf6jGGxygcDfnymHRh22Gz2bbX3EoFKH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RF2cHEd9najxuT8DfsdQRAt2TZVcV2gGx9': {
    'private_key': 'UxZiFtWkLspmhbehzgxLme3oN7FDDy4gokQjLUr1tBJgB829GurX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTs7LGd1XFodBcgGPuofwgCLrrcdM4ma99': {
    'private_key': 'UxHryv4Pkrm63ZG67tD1c48iS1F2njU8Zdi4hDvs7amKePJt9AcA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLUG7UxTjhchVTBZn1GGz8mG2uWYbxJCdp': {
    'private_key': 'Up65dfesYjgX4Fc92L3An6VsAnTGE57hYuE582zMqKTSLWLsPVbu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RC6ZARt1zSxuk6VQLQ9YffMpVBo4aq3LeK': {
    'private_key': 'UpxrfRV6zpJrfQ8ryoC36avinCCPQSJ23LcJXvT4D9pBXswuse45',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNbe21STb73BhEsiWrWaJvFmiQ7YnmkkMi': {
    'private_key': 'Ux2NFrBNT2juBF41cRtSxyGeRo2GgvJbD2UvtWVeectL1GbqesZx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPBkfczaUwa6AqStH3qCuDbgC1WMarkxCa': {
    'private_key': 'UvQW97PvrqfTM1xvgWDbdRjKdbTpHXghGvmkKvLQ2BjCFs8FpEZP',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RECKnmr7QaCHPfr7jqHMRzqnSmyuK8wewx': {
    'private_key': 'UpfoBx8B7nWAxMDrz7CiPDDzn3B1YCTZHnoM4LV56KVgajNjcDsn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPQBBFWu3cXSaxsYhu6LK5xMhTwpRq3M5z': {
    'private_key': 'UuK6RJQWj8W6srWpLn7EQ88MKSnr5iXUJYaFa7qswx8phNW1cp9q',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWTp3ML2G5HX386YYKcZbJFVuWhRRAZnZj': {
    'private_key': 'UwrfH4fM8Z22fCovomZhy4rAZfqqWc9mtBgcmq7RFL8VJQxvZGYs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9dR7tKXrw1JqnquYYEQRxQNnKqLSGzEoD': {
    'private_key': 'Uu5xYB77UKaXkM9PBg6cEe6pZAVgjmBeax8ufUMgsXFLbXpzBZKS',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNoSHqYZDB5qxZHvNT3ZuZG5aZ2kVkAGfH': {
    'private_key': 'UunDWWy5Q3R2z61C1SnTeoB1WWoexNUx66NgcUNShu6GUJJESwSz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMDzApsu9cfFCW7LS5bqHMF9d21Epy439S': {
    'private_key': 'UtQFxJUNFWH5kjr4qm55z5bXRi9XxntjrTdxRQcfD2Y1juKxUEBB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REzj7H5USbZh4bDfgcsc3r32XSitNGcWrK': {
    'private_key': 'UuCYbnSFYS2EqLwEbZz8bKw8z6G1P11CsgQsbAEQv5xTeLYvLewU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKz62Cro7a5x5z6o3FhHFTUk4zYTzpxXNk': {
    'private_key': 'UruFcc7B1aumVhDrJthsNbyWMY4YGzxnHLH1PziCRJu9FCEGPJa5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RY9qsH3TTZLvUuvpMvDEN7EtNeWVScxwBz': {
    'private_key': 'UwKG7cL5ggxqPt6o4UwGaJnn9rLCczba3JpPDEYtajyGe8wSXe4t',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHcEDLRJ62EYLtPL3Q3Z3uaF8V6jKcja9M': {
    'private_key': 'UpUVaRd9VHW2qr5aKcNgXrJiS4vddRRueBSxkyT2mLtGAPVUbiHL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFFmQGguAiBXhmbDGz4eYxyuRp3TNah1Cq': {
    'private_key': 'UtfPXCoiNiUpn8TXeYbACejGwf3H7xpepyoV6GYCDpCjDpkVtX3u',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAAQhMUWULsqLZfRJhxQM2pUhYn3EfJidS': {
    'private_key': 'UuQ92LmQKR51PbYCviYX1NDgy1afNjTG2dApP4xHJYXqo94C9Jmh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTExQ2TS215yBwRJmgAoqqaP7M8e7L4mcs': {
    'private_key': 'UvjWbQn52hYujmV4mgaDuA7ovWeBUqgYAu8in5oMLaJmgPSKa3W9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RV1qs7mQoh1HVgXnXidVuAF8rfUsW3t3at': {
    'private_key': 'Uv1KzCzdmeLfCqKzJ3D4iHG2guyt3vqgsLfhEW7u2jfwPJAp3Lmk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQzLgPPTAsTo7uV9JpaG3vw24Ms4KisLBM': {
    'private_key': 'Uwu6NfSovWZPFwxG45F9FvMCKjrksCibYkBRXFaqKjDWshhJjURi',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHdmybVS4FKKJMsNKoPHiPsmJU2VMskcKx': {
    'private_key': 'UpYz7EdZ47Q8jtiP2tyiCR33fEGHzP6tFG4GfBmVxc2gBmHYdA4C',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKTVmnQjV22iV8wR4MDMN12NK2UVqT3k3T': {
    'private_key': 'UpnuEduBQtk42JsXk7dmoZ3gm37wPgdjqJPeNxbNGE5xCRVNP9tB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RG9bw1EW4PLCYstwPQcavhqyuJcoDxiban': {
    'private_key': 'UtHtRdRtPg13U5vGYp2NRrUS3TTL6EQkqmMqJ9n5RPrzWJfD54qx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTCTBgA3f5S54d8hCnJVNBst9qd2pHNQY4': {
    'private_key': 'UsQuR94RZjfDQPRCAtdroiFP76AzWYpNKn4Vg2LQUuzPNfnKnrH7',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNUMtsLfQXCqPyGWaAd2vGqSP1H8X4PtDe': {
    'private_key': 'Urus93XNabnVcHz5pZ9SE8K9tUKg1GEFzeYwtmA6K7C4SqDaFbgr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJTy11VQS434Jw93LFXxeUG79wp6fy7wvm': {
    'private_key': 'UpzBphRrduckP1RWovtEMM4yHY3uL1XMyQtZQtugrjk47FgXwYUZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTHtWSnRGAZgkT19kDEpVBkM9eHJfmmuoU': {
    'private_key': 'Uue2st6Ru12FBu8T3y1EzJzMrgWMhPxYr8DzTpPbGKFc1oUdNrxz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJc79S1jUKsDUcazJ5S4zYVS8VuaLivkox': {
    'private_key': 'UupMR7uGvi8Mowwj3HtaNazx2XTmcwzK92GEaqTE2QHTKBeub2Zo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMT1v7irBAu4iqeqxm11XkyCYYkhMdVHsf': {
    'private_key': 'UwQ6SoCk3juSmyk8CS5HrxeA9zjD9UwdLgk7irbFjdJcX1bLEEgk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RK844C6SCK9oqNUhEeqQiaWAGw2AcvR1w7': {
    'private_key': 'Upm1WTFfuuWSPAF1xQeo1dyTYxnd7GMM2NvHrvZKiAPxuEceswnp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNg7KWhrQKiXVubn1gGPXBksJRLsJFZvwQ': {
    'private_key': 'UpfoVXWKsxRQwwEQsYowq3KUtPFnFHaraqzZd1f9KatrDnjJRgGH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RE6yGW27Egq4LetXYWwEEmX8WBGeVHMseg': {
    'private_key': 'UrWzPkCmjyQKdFoP9WD8fPYDD7faoLsXMWwShEgpKpcxLQFcusmx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTYh1pGirA6e5PEyGKU5yG94dAqRXvMGhH': {
    'private_key': 'UvZjTD3ctdAkjnXwzCdALifDt6iZAVq88acyvLitYg4QsapX6Z75',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCVHbYudnAgg3h1Rhf8fHQ6efzWpwr9347': {
    'private_key': 'UuC6Ygt7HtHNpm4q3SfbkXsdzVhyqVpXfqmVJjcFUEEUSfoiU6MG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHvvm1gdPP1fBRD5wdyd6hTnMA5s22frKh': {
    'private_key': 'UtdEo515qQ8Ln262yjnhTBuHpzqDzAvjw5q7jNuBnVZB1pb4T6gQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL7EBz68RbG9vtcp4rkiYPzPR9eiZEZf2h': {
    'private_key': 'Us7hQdzim7WYAjrus4WKrpnae6aR2PoKRvm8Hh7P6FGYhXW4myi4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJGmBK331yv9if5S8TKcUykfgykNensfh4': {
    'private_key': 'Uu2zA5Fcj8hnAjnwkTM4uwbbmhPjWdNjmTUiTbvxjKMeBauJn2qe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RH9rrPkN537CjVLXSSit1SEB6JGVej8sAi': {
    'private_key': 'UpQZJbeLyjk94JXi2mRk1X2YQPgXvnHYUjRZ5qECz3yNZr73Ap7U',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMTj5K2RrADyouhUeb1PtUxfbQMJxgwBgy': {
    'private_key': 'UvH2CErXZGSXCwGqYMcSgHob3bgNpNfPGdqmW6rGoZDC3EuB2wdh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVMZnhnsvfdtyR6B1Sx6kifvsjBdWXU3xU': {
    'private_key': 'UpSG1uGCL8LwcmWmC5S3QS2igVyf5QX2yZoDGdeAUPfq9b7oq3N6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNcGhP2eaZrwi5NKEC3keC3GHUWnqpx3qn': {
    'private_key': 'UuzXDHWtr4BarebmJMWkaWhdxusKBrmC6KLAWAkvNBarCdmnc1y3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSmXX9oJFDNcUrQQt2Gwx6zi1rdLf3R6nq': {
    'private_key': 'Uv9YzbnJ4fqnsw4eKYUAYZAwPHjkpWeREoKinC4V6PTzCATmf2vM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REsqxajKCUqEmf99Ma5UwQcMELHh7ZUU46': {
    'private_key': 'UrrXGyRZHiTH2NsT2D9NBg8jHfd6xJpHAXnWe4KcGLiT8hqGfg5p',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDrg36M7tpH96ecX7k3CBzBChnpzQFFUsW': {
    'private_key': 'UwB6vbkKKrkEJsZQreEuTkapTTtYUzcNGUy2Eun7wY2qvWpfkm1v',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RY1KUgLrFTq9JZabddzC3Fh2TNuS2yEwC8': {
    'private_key': 'Uwkrn9u2BJiovCpgrVUC5V3RdHLLbfbigWBhYSFPGcS6o6CUndBb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNXQnHYqejD1HF8DpfqTw4XayJuJMaSvME': {
    'private_key': 'Uqtq9HqARFvmCNaYspQKNwrAVCELoeKLCwDXzS9fuG11uftKqG4j',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLHKznwCjdWbmmeTzXZvzgo8R8sGiBSxPt': {
    'private_key': 'UwtWmVKPYeBoSn5oNG7k7N2s5k9Jup6SheWxAWM2SS7qoxgrQzWp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAd4DhUCZhRLnGWAaNESV8XhWeMSQC5Kuj': {
    'private_key': 'UqetWf5Suoy2gXpYuZSr5TX4jJD8N5DrmrZETtvaEACvsviWthYs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGkUC2jKBrxRcNoj6QyxejDbhobaDsk5px': {
    'private_key': 'UsviBrVrwDCTwq6YcZudaLmGChKDDsGPEm5LoFQJjfc2gDp4Fe1k',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTzj6fUtSMKC8NY8igXXbbhA49Dd3HuMyH': {
    'private_key': 'UtBKmzcHF7wHhza7WTvoEaSHghDkpxjYFLmfvyiB6zWuEn8sq52i',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RY1L5UjEppK7hY8BcNsc6qxehpXuU5ptWy': {
    'private_key': 'Us6YJHdAq82u8rPqTXkfxJFFfjvsfeDNARLSLUW5WZyY9AcUvHG7',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RH3QkcKHgvpJGmrihphF6eu4d8jxd6nmmz': {
    'private_key': 'Ux6jHzpHvXssA4W8GNJnsHLEm4sY1utnq4zNEQc3ZKcWC5aKCGJU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMacy2pN97NEy755sZKk6joH5qANXd3RPe': {
    'private_key': 'UsgvJHrbJUt7UdtWgs6YJGHpT9FEAmiYZ3ZkJYBN3CB6sPpNm7JN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9xscBjNtiuSvZcadrgmmfFxn61fCAqiMT': {
    'private_key': 'UtnmQCT1Da5eg3YgRz43HDTNNNqLaLin7MCtqbkYWFV6an9dJEae',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSRJJEV5oms3J1pKqspfBN2QNxanHZX4Bi': {
    'private_key': 'UrRjEZBJhHk6xesvzvXo2cyEQCxtyte5gN7H8nNvGRT3X7mGaCdb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCekExwWhJZSAGrscPXQ91uHcKJ6hMoVm3': {
    'private_key': 'Uvos74Mi1kmRfAFcnEKWRRKgyiGQgu74dmDFRdPPmvuaWkSwoVDk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVPegtCb2UcFZ7NDPSBCcFSmRrGaYni2NR': {
    'private_key': 'UrRt3DtennbHY4Zf8HcjUJss4GhPwzBQgju3BgQSYqbqfxpuawZv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKuzbc4vavzUJrKB3uwk2eAWEZc6schcsW': {
    'private_key': 'UpfFK1JvT5YbEsNwUQ4PEk2UrmM3CgPKnJJXP5evphPpfKWERY6S',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKLdMAokS6iYvqkCi9sDxHSkc2wdSkcZvZ': {
    'private_key': 'Uuez8XPcmwZWqDDMJeYjUDEV5gY7hF7GmyBBHMyasifWzn2Qgg7C',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RA3pQoE8Zxnp9YFQVD8tkq4KqZ1w3etiEp': {
    'private_key': 'Uwq8b7Y25XgujowvG4A52a2MTrQHcwy6SqaqKietajEn8NUFdN31',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9ohtVXYkwTHopeZ7pX6TSuYm3fh13XcB5': {
    'private_key': 'UwZcMaLmTMEi84Z6pP8E7vtwqBwyHeqdZBdzkENHYQcKgnGRzSsz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQDWEg8XFRxmkY1sdMPscyYxrhdbFF29bU': {
    'private_key': 'Up9gR8kdsGSkabiKEaz4zapExbBRTQTvBbw49T1DazFw6pJsxZb4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUoNi581HY12rgQzH5r5RSAYk65Ym6QFS5': {
    'private_key': 'Uqmb4oHVoiStu61hyfR9orzPUfYnfrkPWMyY6DtH3qXhUSd5eZHm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RH4BZTUzQzg1JmguNoCYon3FxGy4oENtxP': {
    'private_key': 'Uw4EvwPXLG1x2QGRjLM2x9mZEYMsJSF8U2qJ2qLUeHDP6pKU93VB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RW9PqpfKaQrQFfW6U7XGGMYNi7t46yjVrr': {
    'private_key': 'UqM3djzMCu9jmY53gB9yC2S2UUxyM4XbWFxqT7kckX93xdAbF8ow',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLDyX66cxfEgR6m59Y9FNXrMNUCsrXwLpy': {
    'private_key': 'UsPKMN2Tneo2AY58jZfyxWyoMJQaqUBYBK7ZpjQBfzkV9pv7m168',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCmyApDtRdgfiQig6KDMSpEx1zqDbeL4VT': {
    'private_key': 'UxK5h11yuX9nPeZo9bMAycpw4V53yBc2LDbRdSAqUiuyKngskPtN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REk85VuLZAd9eQWgZuyHtv3Zh5P1nMAY6M': {
    'private_key': 'UrLgThachB6mzDg4cg4TwpqnMGUsUvSBxD61GLB4vZMXXYKK4vrP',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLrDjVgvKc3jVrhrqEqDFLR9bdm6tVZgVQ': {
    'private_key': 'UqA7RYdWHVwfND8NS3ZyAsgWS4o5gsPVuQhLJQSwy6hTDSbBDUCH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REsmUjnBxqUChtmVcRSSgJZSwtkG7smPgA': {
    'private_key': 'UwBJP5NKvNev8nyQZnZ5aisZpSX3g3RzDQ3anRZGL96hcGFzqJpw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNX7iEX4wjxD4JdTwwphbwBSJ2UeJf6T8v': {
    'private_key': 'UxFPoVfVjx1exi9UTfmoPm6vQbCwBioc5sWiFPkE1EsMEULEJTzF',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNZAxV269s8zr5GpmsZfYiCGU49hNtq57x': {
    'private_key': 'UuHhoWePDZErGBxxxVt5HH3yuKNEj6UpSEB5n8KBQt3iiaTUR5mL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKZPfgWRBWjPLVb697EuZCr4Zz2pDhxm51': {
    'private_key': 'UsAmzCyPZb4rTtuFFZU72B6wy3foiHJzMuQJWyLGJYRRa3mzqToX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLjegyFRkZrVVYQf1mmLstWaYBBHizKucD': {
    'private_key': 'UvwVF84epDvU8HXHeM5S4BQFNGLscHPnKxWUXkMntaZfJVGV9koG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJ7qH2wK5gXCL1hXhoQLCRrvRALjfr2TRG': {
    'private_key': 'UsY7jRpsVpHx1GTZT7n8vh8ewyY7jp85BxSgWM96vAwVwtZEQKji',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBaJYN5NrNRwhtcFGabjEqQSbhBk5QRG9i': {
    'private_key': 'UqcTPNZ7JhxiEAXvvKSroSgz1iCcp7JGXT8RTbY5xGEARyZ9JPqA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDnJh2tywczfckAb8DhvUA2gjbnNtvLRpP': {
    'private_key': 'Uu3ToDZeH4saahANZxGH8rAAUVAQMX2XeNt4yNowy4DaNqG7dyif',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRbjbSJuYX7BG3ymVD5pt3KZNfKcmjFCkC': {
    'private_key': 'UpxwN16eqN77jWJRDRBVdWtsjDX85RFSjEdJW1e9xrm9urDgTT6D',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHxJkD4gxQuk1A117w7485woLfKfk1GpYf': {
    'private_key': 'UsmqUdtaUQGnQTRVdCVUpoSkLTEf7zbDqdAzC7bLkiJSGaMKMwYY',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYLu5siXhf7Ycegr3uP67Kh8bvdJL2WvAn': {
    'private_key': 'UqfQXyV6SSqXoEvkT7WZx3acPE5coHPam38vwtDtzMgmxkK7WjPE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMZTbLrVfQuKj72pBAfNJGgvzrNuyaG8s6': {
    'private_key': 'UrCiPvcUqSsv9BdLKXHWgrJQUZZSvote5syHy53PqgctV5wDwtPw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHqz3Vv7PDpvSjB8dSyatAzS3CQaTom5ZD': {
    'private_key': 'UtEHAcuKu7G3Ge8Shd9Aw84AraZtRq6HCPYfgfmybK3zFL6iJXgk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLzMZtZr7GFvoPTA6TzEDyyAsB8u1cC3Y3': {
    'private_key': 'UviibQ8qZPv6W96L5MktKFZguTc2xciVfxJBT4x6odEy6pWebemx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSk8vyg4n9VJkubeYVVgq6Rd1PkTSRL2Xn': {
    'private_key': 'Uuao8ikzerXw8ZdYAQUBnv4MgDQ9yhbZZxXM5zEovV15Fw63DNar',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRtFyUT6VkSsgqeHyKv9otEwDHQ91HxrLM': {
    'private_key': 'UpPZZvkjnzdf9Ke7pMpS2MqQ44tLXH2crParUBi7PKPC4YnbgV1w',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBQBNkkLaQYXwDuNMkEHoWfY4ZzCaanmgf': {
    'private_key': 'UsN6PHSgNzfwGzCkcWTWF8dJCxiEWqRPGLxpmEr4JJRfw2HmTPSD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHPDRkWGXnf7jxVLpVQ6MdsggXbskbioDH': {
    'private_key': 'Us2nvt1Zuo4duBBeHYwTVmKgnNnAs3vFFPUi9NiuNrfLUTjcduLp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMNv33Zv9kAsyejmN5JXsgDsB7WxbNSey1': {
    'private_key': 'Uw5KxcYSMxfaopKqBrD3XBYFd79i258KT8ZCy8mU6JnRTtzuu9Dg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBCmc8L2QPfYp52tdWviWJ4C97PzrEi6AJ': {
    'private_key': 'UpcrQxoFnyxntQnHtmkGT4N2dHrnNkSzLeZev86uk7rvEvmNsDMQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQmSz9yNKiYTL93rBBdN1nje2co1i2P4ph': {
    'private_key': 'UpGr5tX813iJ8DkPvn8BoDd367kXEaWXGodeNHVNsJ56npLvE7F7',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGC3ujig5rkgVpquQgdgw4pBB46tyPDBod': {
    'private_key': 'Urozb7a6S8YwU6hpaAAvemgJtBHTCnATQXdMXgpFLCowwJHgRkao',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWxjMsoSLYhintUA4NY6EdXVfcUQwAQiJA': {
    'private_key': 'Uw4Xh7zNWa8P7tHybGHfUc1gUhsq2fNqFS2XSrXjYwBUnpk83yVE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLRrxxbQvrk2q6BDRTgN8obLC6ae3e5uxb': {
    'private_key': 'Uv5WibeixU9RJmxD9hsfokGUBjmapkaZ76AzEV9si5VtYa8vYrLt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REJj7Ayd8GeK74FgrtpNbV4UaqCdH4TQ6s': {
    'private_key': 'UtT2SzjDhsRQ84qKUtJ6yo4Tf6tmDE6zdixca2pSJgTaFRUMQ5tf',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTmuT7MjyExEbdrB4fhxRAnaVkH5oS7miy': {
    'private_key': 'UsTADjkwCrArXL9ZzA8MjH7Pf44kJR8JXRq324jEXaAvXqHTrib6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTyTB55yWVA3DDBhacmNCiMsrXc8Q3yG6Y': {
    'private_key': 'UtTWxTzmNR6E1aF38TEfAPf8yGDSY9YJpfqZ8CEw7ofy5N4ksTS4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RK8T7C4bt8uouFJEPJMUycPcHqtT8QFkiy': {
    'private_key': 'UrviES9g2ZP5Q3HhCoMw84caDGQ45EZ4mfvkiMTThwjap5ghmBwX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTYeTidUMyZ9wfD4bBbMVC1pymgmiNHsF7': {
    'private_key': 'UpV7rE7vEVp5fUbEgd9uRqnGFxawDFYpTNH5L2HZWuQC7RsmMsUQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJjWrez9QuGbgmyzRNkD7bL8QQ1CtkzzkU': {
    'private_key': 'UvscBXMsamfQsZYxbUhAMRHZYkcHg6V3tBTBA3sKiMMG4cwxdQyW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RS1Xw6v7cQuFHsHYhoR31BncWSHvTRyW53': {
    'private_key': 'UwNTiU1YSGPGGcuaY5rwDwe3URd4oCSqHznM51nnTrjDY7No2ew4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAk2jGoXjtNsKbEenHXMVsB9NWLSbHeUS8': {
    'private_key': 'UpJGcjcddf5vvSnVVjPeUU8tfLi2Pv3SmCCTtak59yQLmpGQAXXY',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RR3DJnnGtf73FnbfZbZSW1LLuvVxq4hzES': {
    'private_key': 'UrAukFVHDDs3tg42f3vsKCBaTwfjwcxzHjnNQExRWsEminHyg23q',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCc7zzsRsHCNfkyrmzvSPMj39N7ug2oBaZ': {
    'private_key': 'UsqoXUYGr5z51LNRMLD4jWNWGeztvTT1RPkaR9Huaz2sWJAbdDCz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RK1Q4sGTyPusRiMn1vVH1B4Stvf9tPqyv6': {
    'private_key': 'UxUCTn9H3EfjPpQSFDBAFNfdae3Z93RXM4EwTMrGjS49hF7uDN4e',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPgSDyJgSjV9L5NKHPnsR489V6mqpVsqDd': {
    'private_key': 'UpD5WzD4LUi9dB3ujsuYoezBjPVsAxjtS7t14188yhnVvdSRht4K',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQxaNKAKfghcsNVUegm9qDn6YctWrVDtip': {
    'private_key': 'Ur38vxEnfL8pd7snQnAffZ9kcRtDNfzNGmJ8tXnmSfXLZncsyeJj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTft38EwfGskVQBuN7ZzfdimNTNYPHCXhd': {
    'private_key': 'UtwPsbwASN5CieX1KhiiP4M286iqi1NhHax4fQkBnoTfx6QVTihi',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMgcVMW99Dqt8fVazu9XjyfZugi66XFTKK': {
    'private_key': 'Uqguw8Mkx7KvE5oi6o9Rcj68swUh5xM5x9pC9z4Kt8Ead5upfQ6N',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBELozudXkG7WGGppYh1rhGPbthm65sj1f': {
    'private_key': 'UvGEwc41xkTHvSCufxrdJ8ga7ijY39bez6TFmVbN4RwB8kr7KQN1',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTPH59tmRbEqMK8LouiqUaUNJfd5RguivF': {
    'private_key': 'Upyjk2cvzHLJbwHrPTbNJa7dRCBZ9f8qPXCjCLeJPDT8UpBZBWuV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAxsqqveHb4b7Se3kE3AEDiuiCG4PvD9YX': {
    'private_key': 'Us3BKm3S1Pps4QmbC3exbtrZouB3Fww5j1UZKYDQVc38qReJAp9x',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWtYPDzUYz9C2jzmPjnHzEWmHk8vLYc1Ay': {
    'private_key': 'UwUySCTu7uLGbuZs8PY9HCmUHB2qap5UGhv37vzYza7mGh4XUP79',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWeQVGKuNboRn7pitsnFJ8diVwC33yEdbj': {
    'private_key': 'UuYvjRheSB9WgCsNEFUbGsSnjkDrn1ozd8xY5u2owJ2svLRwuN4W',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBNfmWvrZoEQW3EuypeTA9eJSS9DR9Hkry': {
    'private_key': 'Utx9cLLTkAegrfdv5wb1SY9Yndq7yfAqqjdDqdHV9VWMSrJJ3pVz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCqN9KwfgkAy85sr9UfRRFE3FYi7YScY3c': {
    'private_key': 'UqCSoPiDE73zKVxXZePL4LnvpgUM9vo72WvTYjg7gDoVdapiJHik',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RV4zhu2LUJcgYpyx97PabSiLTdGDsSU715': {
    'private_key': 'UteYHnp3ZhevoW7ZRkR5153GAJ3czCv7k6TEjmzQKbhfZ7CwGoZd',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLSSi2Hb2E6evn1GNiwrjV7nzqEn8tPyTj': {
    'private_key': 'UqNQqUR4vvb2MG5iz4m7ydt3D1NJndevE8t8bzmzFuqaSD2cUqou',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDPq99CYf41tkQ3RZBNG9oX9sWxPUuYi4r': {
    'private_key': 'UthdESKiNbYrKQc4MmBZvteXvzoei7BgBFpTgj9SEcTDpGRh8GgG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKaxFB4vSdvoEzCq1hKiYkSEUCeW7uNtEK': {
    'private_key': 'UxCZCqssVot6shC6jbjVKzYtYgAASoapAw3gPf8x7TPbWgMsNV8d',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGTHJ92A1t8kfMtqDEGjzwX2PKGZZ3YeXx': {
    'private_key': 'UqGGfnsZ4vmt5wLRNAP8w2XbvXcfCsFXxgsHJUzpDkcF7PYUTYZZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGFGzgRE9UU24A7edHHC2wTHTLhCVN6qQg': {
    'private_key': 'UpkiaXTmp7YUcTiNqXMrjnzt6LktrQHsQPnSMENQkZ7VZdQRGtJV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDHxynC1ewSu9Ru8JsvC8XBNyqdHwfe8i7': {
    'private_key': 'UrAyaBzLNWdBPG9HpKe3b7APkAGP64p9skAjQSM7ZSo1mt77enZQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXRL3dvQC7uNT662j4RjgXbFf1wyaPDQ9r': {
    'private_key': 'UtFiC5HvU6XpxnYz6wjPTvUkDuBg1Kqx11DnJZEMS1UNqwTVsofC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXAuodFvbVkozoeHNrLXNLGQxmsq5CjDFh': {
    'private_key': 'Uv1wP5spba3xuvSWkZsLWpvhYw3pvGjbRPg8uERhrajhACPmANVF',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYKV3qwDcN3iuUSGjLaipTwMw8pavwPR4z': {
    'private_key': 'UrT1pbpD5X6e4rpyhSZkghVBfk9ujy61tLGiMmdFwc3NBsFMt63q',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9ptx9pFVDCy5ETbbyhmGQ6JngFXFGR364': {
    'private_key': 'UvHD5uAMQ29FG73QtYABN9KqJzEgZuy73X8y3TZgGKbu63moCsu6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAE5cuB3fohoxkLCMbuB8v61BV1GojbEAe': {
    'private_key': 'Us6HFtm6Y2M9ZCdn4cwWAgEdeY8wVoooCdweTw2hVMiv1kGj4rzo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RM4SsDarDNH9hEdb4e9rx9aUqd8qvumYB4': {
    'private_key': 'UrnQW3HVUphRwM5PbWRnPp1WKdbKWdTyfSNez2Gb32tUZq93Vfxm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAQJ6uimuxvRn1DTzit3cN4Bk3fmqXdbkk': {
    'private_key': 'UqYUXUsFTLMhM4U3mLf6JsvxozPGEAuvQWcHtFhDNqpB8sWeNmNx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNDDEc4oz7UPprRCd7kkw5vHMgR2DVyF9y': {
    'private_key': 'UwR5bpAavCqjb6r49eALV3DqUqPHzUjiXErZ9k9AvnDuHfbB6mbw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RY8iT7bxPvG3Z3PBAzM46pmVdqvRcuKywj': {
    'private_key': 'Ux7rACgP4jU8PeG9JcKQyMZd5WpTgFDKU2xSrdoLFemDECMgm7QN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFSHgvvrnpYR8WZnhGr1xPCZCAjuRqgaKx': {
    'private_key': 'Ut3tDP2EwjYKGkGkyWyQiqpwqYRBpU1GXnNmDYJKtnCc195Dn5W3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSYNKypFHWCWg4po9MfR3YCpYqtGBnAmHe': {
    'private_key': 'UtgL4q57vTosZ9NpdLcgnHqBNGkqAXvCdoyJy8CMY7Z6GBCdkQKw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDhaeQWUnmu8VBFauFWJy4vz7AAvdbKm3c': {
    'private_key': 'UqE6FcC3xrNnMcsstqFPHPXJErnjXxJqVZmx9BoSQtjo6zoFzNMu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAUQ3jQht8UD9LnRw7encE8LK4sESPKSC4': {
    'private_key': 'UpMWHGWctWnP6p9scdV4nvfw6gpQM1fNCf7szkZZJiV6AF2YeXjn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQjwissodJ82GGt7TxyqUD3ixjuxESZdDJ': {
    'private_key': 'UtSyc3nwsQAvkfxvm9JQqWjNSHRJmu83zuEyetGqYXCva9pTue3D',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTQvJmYbM5SNT7RTpAupcvBijXDDR63j78': {
    'private_key': 'UuCYAe3CqcxgWKDCbWmEtVkLxGEVr9RnMVdZGbAYLpo9Kayqbv4u',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RP2sQwS8auvz37nyhBapF6qZBZU7y4869W': {
    'private_key': 'UvV2teqpmej9HJHJHiEPV1giHgpWeudFALNWHw38tb9k93hHSD4r',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJhbN2psnpRVHq1CviPVWEG4o1twsrUnDV': {
    'private_key': 'UxFyn6fEA7YmHNaajjvrfxfPi9mjaEYnHQ9XvaBFXKZ3UodE6Kfy',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAB93n9tUsZD4YjzazeB8g4hkuGGzuGhbL': {
    'private_key': 'UraBpzfz3tT4qAxoB3BKtY94v9errwe6ZgFtdAqv8EuXvzPZxcqP',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVhtQFQwSTUFUWqGsRPcNUU8mRwkJcXdb6': {
    'private_key': 'Uuiuzib91BMCpfzB733uzBnG6wPk44CVtFjWhbkvcoz76kkXNhhy',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCAwQzHB95u6NJAGfofmwmPZQeW8z8G4ML': {
    'private_key': 'Uv4GZ82c83RAFvXpoaV46LQAE4hZpEwyen9tWa75tb1mZgTFzxsp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJ2V1yTU1bDfQ6TiXJt9r8JKZLKZ1cyjbr': {
    'private_key': 'Ux2oN3TENAoo5CLrvtu83Rvp1ecGhXo7jt7rqWUx5Zfbv7QDTf23',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RReidU859uTc2dbLwJjES4RWb6HMKJAz1s': {
    'private_key': 'Uv211CwWcMm6HE4i7chHfPrzNTFXosrBkz4dQDPuba5HAVGDHYom',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVq5kw4sUzcYbpgnX1oUyJAWYixRnfrD5M': {
    'private_key': 'Uwh8aVmDN5eJHKys5B9HFx6kZtqL7uP69NdGNyLFe21Fs7ECRXkk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RF5uSo3Sa2kG2voHNrikLHmjgqtXB79Qsk': {
    'private_key': 'Uv88HEVVn6pvE4FczQe4BoPxPuR5d74Y8WSpvqtZiN19dHmw397n',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RV12My8PxFEQnmgUPLGk7W2ADoNdsfa5HB': {
    'private_key': 'UweWV7mU1LQud6ix2sVJW2WC6Li2127ep5j3ufrXz3Run28Nzhsa',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBZuRWiB5zs5M2abbcpsyWFM2cvDi39FVs': {
    'private_key': 'UuzpxFYmqgfi8xkGW99tqTNLP2V9jp3Rk8K2RvWQZtru1jgkxadA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRxqQin7xfW3jFZZ2fr1FU1g1zcyHarWtP': {
    'private_key': 'UtiuG8bdjDBvi41NuEM3kB8sHfcCTEWkxGRQWaHgZ5Ne7zUeQp9z',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUNnxhVYaPmjB3kHnKQLwwW831H46Jjvgi': {
    'private_key': 'Uwbud58Cc2fNXFN78s9pLkeqH8JMmEpSKDHiuf2fEUhtr1HeHPnj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9MjvkEzjx23x1SJpcabZW53GXbpgvtQpU': {
    'private_key': 'UqgkUZkf4sAa5JHhtwgBrK3Kac55HvArv6ovoxdGTdN5m4DTkgvW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQgUUBhxoQJ8w6qeKahD4VF3xH6PPwJ7ye': {
    'private_key': 'UuzxzftC4Z9R52NCioBLcjKqhf1mu4ivxVd1Gu1apErANrmnksHB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWaHoXQn3vNroLvtN2mseMyquTGrvxMpj6': {
    'private_key': 'UpCVVTZw2c65m3sx3izDcxXvypaCntUmb3TJKWTSXECHvaxCe7X8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUfkQQ6Uy7MCqpkFRUDijBedwAiG13qywQ': {
    'private_key': 'UqoVBRT1vwUZho7s8H8PYksLJFeqRxLryQUEsWkdZGKyaUecKkWE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXCm1Z9ReatJ8VGkNeMQ9vHspXjCAiLtBx': {
    'private_key': 'UsT8jpnB6kFKrC3accmd26G2fePVsgFLMDin81WQsy8ZUsuTK8CE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVpVX7gTytPnQHmt8Ua4XZLm9nuVvMHeJy': {
    'private_key': 'UqacQnDvVQDo9XdMkU9zjnbAkfoitvNjJkGk4JpBxqszqVpZoPKq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTJhQFrK8RPFSjjmjcC82WcJpqtYt8s2Cw': {
    'private_key': 'UtEt4v8UnR6xKi8yLhNJrjdsps53yKYWg7gP7dAJ2La1xcbGgwbT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKJPiEG64X7d25iMkbmBnKWEDzL9NtvEQk': {
    'private_key': 'UqGvDtLsZQBFR2v8gbciPDXSkBiansVXzkZZMLGYEKYtjvkb2nty',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQdrAZBhVzPPeWDjXb7BCbC5RWQReRFDbr': {
    'private_key': 'UuiEitU3WQjrN4kVrYirErD7xPAGma5R3wLvLWbaanBjdiXp2jcp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBhytARCsKNhECp3494Wfkp4NcYaeuGBAF': {
    'private_key': 'Uu34oKdbjV8zwe7CQexHphPepYTkTsXeBvUTpYp7si9sZ1ALffCA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNSVg8hniKhkeeiKw82fhBp2P2UUoM3yZj': {
    'private_key': 'UpzVsqmf3J1xSU64WgthorR6CSwmzdGiovJcyjti75b2q3dWQvYi',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJrxSUNyqFZJMW9EffZS3q4rxqYKcdxRyL': {
    'private_key': 'UvprvwKr5My1k48gZ3sogBjSRTYVZvkZPiZtZXrZ7hYzLG4MiHj6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKNXzHeiTciZZUXjssQ7LbfsCcBQBUnqDn': {
    'private_key': 'Uq2WvzDXRqsMcUCWNmrkbEvhGLYkFr3C9NbHMraMaUuE1E9vQp4f',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYG8R28V2sv8DJKAPkBvzWog19vMLxNj4X': {
    'private_key': 'UrW8nDvxB16MLSPW7QiPcW92fWkwAo9Pb9BEVG7RBo85JkyBqfiX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNqvKoxkbfHFEv5pVY3CGm5tnck4o46FHn': {
    'private_key': 'UsJbrSAaJAFP8MSVPdenBui5bKxcgzfSbyPafm8EDWmBcEn18y12',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPt9G8HgWb8469M15YqRoqrjhSVzKLGuMZ': {
    'private_key': 'UpNxsrQhL7X9BjTP2y4GfW4ELQpcGWjD9Aat9kwh4F74D1EX8aZn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTG86Fyo6SqvhUK77z11qv8YUZPSqKYDnP': {
    'private_key': 'Ut1BnRYHCmpn3xGmQG2gsvN7CUPMXCyKzEC5R63KCniLivCgCuNc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDGWzevBCrXhq3wvJPRNyN5gyLHhmybDya': {
    'private_key': 'UsSpokCUvJZwuEt2CWKEGsWxfmjtdDqqf5tojvvpkJiToB3tFcD6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRCEGAdf7wMHc9nWLBcMMibQxaejb8A1Q4': {
    'private_key': 'Uv9A52Q56XZkKsTkmkj2dSrb9mgo7qkCQzWYbwpYEEfHj4w7xMsE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REvGTd6Dbpz2G5e8kuT1YpB9LRen4Qfkxu': {
    'private_key': 'UpE7UfXQvxC3poViS3VRPXtJcYi5yvgxwAVqt299carBt4DD2s9m',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGjNcSibAw3DGgKiL53ibeAbdQbJCMR6RX': {
    'private_key': 'UtYaRMC6Dr6iKwezv1z4JA9ZPdb6FB9eqAW146JigvYGWZzJRosc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RG8QYhjYULPTy3Eko8NwJ1dxuC7jyHJrPo': {
    'private_key': 'UwnyYgZRRGScVwvo2Btrkj4gBg1VJZdk71DbfrMhUshZiDMscRQx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPWqFZ3eR45i2pF56va7zRTMZ6pTw99eU4': {
    'private_key': 'UxLD214Z56eYbGqdBohM4Qqg2vTGyeMTCZa4QnNJFfTt4sZPvfck',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHcJYr3qQJ93zcfAexZk8Q2bw8ojBApFpz': {
    'private_key': 'Uv4US5DwwmacsUDBG1o1wCdPM4Ni4hPdpuXG7s4eVC36McUAQH3k',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RThKqk1r24wxyfDFDD3oEQRSXwNZmxdL2U': {
    'private_key': 'UrshYdaRXpqs34Jhhrj97YdRV7AoT4gAPdZocTeohqJnyV8hMb4R',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RU32P8sEJ8qzfDh15qvqUBabWAw5QbWBLA': {
    'private_key': 'UtLYfr8KEbJxC9TS1srWzUF8uGcn4UnuDUUd1vmNr1uMpVWx2V9Z',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWzsFtgFXuQz9AAhdFVwix8UM8MQn9uWxK': {
    'private_key': 'Up5YLaLTpyFzwRTKFpKCg3MtaaVKBLq7ZxPc2CumUdx8etGGdm8P',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTQ7ysgQVPYxztgVHcLX9sf1aMgNbqEfec': {
    'private_key': 'Ut3rqYkR5ZjR1d4NZkra9tBYW6gSCMhRS2uezZHcXBP8fsB3BrKp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTHXXfmtTDFzXvwCEmV9maqMiDz5njfZ3m': {
    'private_key': 'UryvXZHsVmSsGAL8RbpxBL1tYCfPgtjuuBhuER7hySuYoBPnQUMJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RB81RqJ7cJV4CJXupCxK3fTJuwXRnSEYJJ': {
    'private_key': 'UuBmYoJJNirb5LqxS3okvwZPH3ia1dZgEfDKCTLHwddERVwG8Xnb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGFnRRdyk9Wksjsyt8rN5us8YiBVbebwyU': {
    'private_key': 'UwKpYYPBm1WzFvc2E85gX9y8SuH13JMQPziPUr5QUURnuDzF2GqL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQae57ZDH5My4CRDeAn5HudkhwL4Fvba7r': {
    'private_key': 'UrCpiWDiYXvgHViFpHNWhEsGSKug3rxkZPQKRLfS6BHB6QMBoRMn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYMXwxfwHUMhHFtqELkA4pig9BWq9P1RwK': {
    'private_key': 'UrjVqgyGM1LkHqmYnpdEZJcjqauD7czyrMVHuyfXL5YCk4aoASkY',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNNw7D49Y94ua2xctisN3n4ezU4bfcwqK4': {
    'private_key': 'UteX6pyGS6EoAMgCo97Lzj9JdX6xENp9sQ5s7zbXrH6gvjbLoFsb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXnfyDoogbLk9iQNrTctFa93fdknpkf5qn': {
    'private_key': 'Uqe7zqrjYoWMGctCQ364cAff7oKx7rmVNEyMCdcUNGyauwcFUymP',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RD4KVfwa9n9BVABYrpQYsQQQSpXmPfJxfx': {
    'private_key': 'UtVz1whWofcQAqMACFtj9esMhDBTHmEjQWYKWuDhgf96x3ED6JMw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVLwuWUpgMeTUoaHvqoAgRyE3NSBvr2dLn': {
    'private_key': 'UqCbcTQWrMzQWgBBdLHMVXaThuEZUZGQCxPuxkwu4jkZxuj4Pp8x',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTp1UDpb55vfCFgtyzchdbELbMnKgzFdCF': {
    'private_key': 'UvADpw1vEV4MAWRv5wYTR62c2MM3bY7BQNvHg1vCEN5cC4HzbXYV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RU93wbpQJQuzL1o85CCJh5tCT3mrot3nmK': {
    'private_key': 'Uv6wyetLqNrvYvaGpwvt1tPN2aqsUpGnRFVvLU4WAtKsNSrnqrP4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMyrELaXJCtRDAckTowgi6JiJ5NuucC9GP': {
    'private_key': 'UtJ2v2ekVe7bjiLYUxawMyk8LPHZy6n2prppqQEgY5YpDqRLwdGj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXRru5fwjMwmU2mTut1tiKAX6w5NZNzw1V': {
    'private_key': 'UrN2fumMJLNWfAST5tvVeLU32t7AwqqXMFHPmLf1y6TuDb1VTLgT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RALkpHJiBiETA2m8ZuRfNo1BPhMvvJv6AR': {
    'private_key': 'UxFammr3J9KgXC6trYt14ACcHqXmNb3gNNhMX1RzJZNpH2aiWsxy',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHQEWxwMXfe31gJVR6EhR3yc62WEJCVbEg': {
    'private_key': 'UqPz3M5V99uCAacKwgrkG27U9e9bVo1MSSbf4FfjUq4pfs6DqUCt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDJCHbjXFkfrHdb6oAVetPPouVDwPPwCdE': {
    'private_key': 'Ur64JkdkiC7F1Ft7hGUYAtwrqGjrK4zVArRauxdeJQ5Ujc1VYBNH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXHuRotK6P6RfsLSJKx8uoHZhordGNEGSX': {
    'private_key': 'Uqr4NFCSHjHUkmukkY8f8wnvedmQ62j2ZkEvquSbbyqXJTPpYdcx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYXRUPAQv4Gi72QqrQw5X3rUSi8zub8WcY': {
    'private_key': 'UpXFfyDwCy9VwY1LmbW8UGL9y2HH9xabjrm7xDUmkZREfQoVgGAn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVdMvj1UgRP9ZVDrLS35WXe9p1xakAzMWL': {
    'private_key': 'Ux3WRbg6iG31GxUNCszgtzVqLefddm2Ef9PrLhHszgwrPHX3vaWK',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLiMJTYxDtHcy8cU5Gnbm2Ezm4ZHcPBLvv': {
    'private_key': 'UqKRSY9U7YQ8ajaGjtZvy9ADVyFkgBbXntxVuozVMLABoAGCW9KK',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHd7HLLbYA899Gqagy1EL23M3PW6ZXB1jV': {
    'private_key': 'Uq8BiqCLYuNjavP9yT1Ge2K1jpqw2R8Rg4jLDnz1NoBA9gNgnNCu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REHnSMQWSnm2kSW4SBuD5wActXhFU98u6W': {
    'private_key': 'Uw1VYb28tK2rPDBemWYPu43kGDmhkhUWdQ3T6WaduGry9UTLtT3z',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHG92ZZumqrhR3XYxfjZzsGMNA8gs6Zfok': {
    'private_key': 'Uqa5rHLhwAAZKyGjtsBb8fCZ4gkZH9CBEDbvf34VQXE2HCEnLPGp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTQ5tfvZ6he8hdVJCMjrHi2RPhqvy1rQHr': {
    'private_key': 'Uu2eGabUJ98s2QT3UMwvBecCKWkMPKmmDqptKjW5xhF5emkEADYk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJDc16UKQHFHkNDqZ8d1tGi6azaKujhTTj': {
    'private_key': 'UwBzynDW8UBJ6iHX8pCp3ViZPSHuBnrgzT2tyNFugs5f3kTw2eru',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REV9Gw1atbJVJN7wF6YMhTXsZcWagKSpRS': {
    'private_key': 'UviaJBBwmgot2fLFAiZJJhQbvfTRawR1S5jdmexsrnt3bgaqhJDL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQYhUpYyDXJoajcHJE5ayKZSMhv7RM3JuL': {
    'private_key': 'Us9mzvo9cXWdkakhnBowEUFWWoEJpvggd7zLsBGN8HhwEQHokjcz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RH9pbwrNNtJHfugD5EaegwRr4ccZCDhpys': {
    'private_key': 'UvNkgxFQvH7UZXt5J7gtYGd8J2CshW1RndN6Jr3hDeK2TmFdaZ1b',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQoAi296q1gC4vrGzC4dRp4NZszMS91v1c': {
    'private_key': 'UuwZditTuGX3CGJW3tGi7P49zXR6YqTtSihGeYjm8BEtu16eGZ7Q',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFDuxh1qanWMGDfE2VTHdvZpCwK513u87p': {
    'private_key': 'UvE8JimFuskJ1A9ENqGL2WJ6BW2HaUbvFRzHaqr7ZD5XDEsTccv2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPvCPyBVSRazBmWyxeDpX7aD3QM2zLsUh2': {
    'private_key': 'UsyR7thDmUy2dK2bsMKzVfnHuEj5JY6Rci1BbmyJfqrpKX1D12h9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDuRsnvzwzdqtiYW4mLrA6mD7JAmWPjimV': {
    'private_key': 'UuBnQCWULsQZKt2Z7GFkS3njbfVvuuNXeQx4AmHAYqLmerPF46FS',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJieqe36LbnPGjoAsdvdj8yWnE1woNrh9Z': {
    'private_key': 'Upjku4PKA88PZS2hWyFJVpcsrSAndMH1ErRJK168x8YECU1bLLkD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNPsgsmpT16woGxzLnaNZW7Zwbyet7igcP': {
    'private_key': 'UucBr8FkQNHGcAGx8RauXRnng7JPLyWAFPtVzGN3yJcCCko2KARG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9Ytup2862ToLoKvLsM9kDPPTcHHs5dJzf': {
    'private_key': 'UxDX46S5EC5TchKaPfizwWaMzHGWBUHE98UQgjasrTMyuJCeMiNs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCzH53kwRHBup18gbUBPif5mMpufM5twwz': {
    'private_key': 'UuYWZa7KeLfHsMVGPeQ2MpiCQJU3W5TmdTwqxdhsF18mnYZXhzT2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXhhDH9Svih4hYs9EHEazmr3G3CzVPcMkm': {
    'private_key': 'Uv9kxw9qU2JRuJjVWZj7JRJEnK4Xv5zA7Ldno4As29TJNDaXgaHT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKTwi9Jah9P7Ph4i8tkFv5ZkbwpV2qLzXL': {
    'private_key': 'Uttkv8su6huh3aZxemqxbsLP2pnY3Jvo8hd6hatXuAuXg4q4Xg8x',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFfuE3tzgHQL9VFYDs918LkoBSDgrDWwjN': {
    'private_key': 'UrRkxu98ixRKBN9TuuTD4okNHc2cU5wnT39LfpuPVrg7g2Hdz4M4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKFYuajpzUccnwfnU2Y6QbMyqKHoeDHRni': {
    'private_key': 'UvTW2WdtZqWbr5MfuuaZBGW6HYozHyXtJEsp5bwjF3YSdB8x4P1Q',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKFnCkSHb2PXSCUUxNXMFEVGhZpbnmbZAc': {
    'private_key': 'UqmW8JLSEiqMNAZgqQhhTDQRVDPMPPkBwWJS4mTqQ8XLTe1TXYTW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVjRXoiqeHHkdChwstGLXBVbtbZc29SwiL': {
    'private_key': 'Uqpy2DkbSC8imDe3HZK5tR3ZciepPk2rcL4mfmjvSfjFcUXJnvtt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNfeX5iDZ5ZyyTsbp5q1KamcycfDmBdUg2': {
    'private_key': 'UvQRy2QDabfv2VA3x5W3hcPSsvt3nNUX61L9cqWVWRGVMTLKwfLW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFNMysDs4vLhgyMqh2kjTHBzora4QMnoA1': {
    'private_key': 'UrEd92yv9CcTmhLA3bBLrSVuquD6v3tmVcGJdmcQfXj8YCmKgzbz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPe7xz44Dwo384g9eKefWE3tCsNp79ioLk': {
    'private_key': 'UqMWumbHYrtfSSEiuuts12AsoVw222n7J7xQeagbKypktKECjX26',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRtR2iaUg2Hjgfc52ykaJEj1F7uKxsLwQs': {
    'private_key': 'UrCMkVUgdNMjPLduZxqzTfhwD5Vv7A7Hg4e3CA3fCFHRBuXvfjnA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDC89rjtZ4MUXmvcpEvKpBwVyRsuCAd2zV': {
    'private_key': 'UxKJ9chaTwoi3B45mPcuzJ4NLAMruXw55TxX1WmpbF3W1N4ULRaA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBqyCswk3WLzRayLkxeJRE6358KuispExM': {
    'private_key': 'UvwNLk1YXF5mWjjx7SVL6nDw7f8vsjSBbtQMVxTQPkEQ6czbxkiF',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMxr5kfGJnqSNV3KpFWCJkSWMQgDg3A7uB': {
    'private_key': 'UsWntcQyR9n1Fp5ym3ox3pfKnqdWyHtKBWLg2MW9Refrh7TeoyiM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGTTM1VmoY7LgToCBzWVuARnhk61Tkvehy': {
    'private_key': 'Uqsp4E7qmEBbjLZSGQqKbXDcNunPijFfyDZVw2de94cCNpiZu79F',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQRzxGR8ioS6knynctDeQCGDSgUkepvyax': {
    'private_key': 'UpPMcuqfrtSEA3yyMjSLszirHjJTALYBrECyHcf13toHvXtZzyU9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RViwKiGN98Wyrwv2bg4mXhupA9ENxnMRRj': {
    'private_key': 'UvTyzbd6Gb9CqhYQgE5zCYM9LQ7PD6p1DB8M8D3W82W5JGAkos8J',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJs2ySQJxdx81qXkWRAHeKJ2G5xgpWBtvJ': {
    'private_key': 'UssAxKHcDZxKV8PoKXKEgzyaQLyKQ8xRASVWohaT5NfcR8Z1eoc9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNHqFDi18nLBmVrnQfBoxFpnjcgQwcNLMM': {
    'private_key': 'Uq6q6q9fSBSzizV8zk8xszfpM8fS22H6qysgsuUGny8XhGdR69j4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXGmV2A9TAm3xLrX5YhRsoKqEZDZSC3HH8': {
    'private_key': 'UsqdMiSpi5GN47YNS3t9N3uDeLMNm3FUckq2nZXSWzPkmk9fwzmK',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMjopm7azsF2kxxmJ1mFfcRNzKCFuzA8DA': {
    'private_key': 'UwcsjLzi5Bt3jzZYyKSDboDCKXd95fsRNH3zWEqBeikBx4ecFZJB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVrvwgFnQxT9isubSJArVvhRPXcSFqGvZf': {
    'private_key': 'Uv7axeocQD9DW1pjaBv2apf8Lv2P1PaLEjZdvCXBchjn4eBPnUrC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REx9MSo8cYiMWQbNxr8ZQjsyuwBJaVWHTy': {
    'private_key': 'UqKG69rprF9QWNBzbH8iNGgAWWLGpdGkKFK9JPXWRTF2Z4vRekuT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTSVZPBEL2FVJeGjQPTafeyt391ECExpYy': {
    'private_key': 'UvUFJeyvMW6GFSSazbug2R97wJZHin9Lnwyt4mzLakvWep8LjpWg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQB8Huw86TVZbhbdL2h6wTYDp45Wnp8rti': {
    'private_key': 'Uw8d4VD7YAxoUYTTG7cgGbWfgYWgUodwP5KeW8QbwgM12yqXkKrJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJx76J7myeS9dHzGcx8bDS6rjZb3FrCNWv': {
    'private_key': 'UviJwBwkVqJAszYUuxszTJXiWYGSNBv2yfFV5S25rpccaQcgLHgC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHgEHihdemr2WfPEA3GUjpvpjVsP3824Um': {
    'private_key': 'Usqt9s7Drn43udkNr5RDgwTnaiWsthAfWt9C62TJo2kL9bWtJ4TU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTA5DQCM9keuYkTGrLwiFahtYwfaFZRoyE': {
    'private_key': 'Ux16LHEsK5Ye27JMVAxgPw9U6QbBA4BXQWp4ToD482hCwCqHAdRq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMWm2jWdaZtECn6SZ75nYchzy6jWyjLvmW': {
    'private_key': 'Uv3iCL6vF1kMqaiC8Auh5TgCQDyBnrYyv8YDZb9BHdwUE7dzAj31',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPYDJbhU4SH7bSop5BExB2z8RuLw7mzVyo': {
    'private_key': 'UqDxT8j1cvXigGNNw2hFVwpuruyvHWGjR5zFPTe3CASoM1RVv4Du',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RR6mzsY5qw6PMApmq25S1fXG6hDhHnjbZi': {
    'private_key': 'UwL6VPQAtbwPT7KEGK3jg3T29AnpYqHq1TVcApgicGdYvxs3JMHk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFwqXQoYL9rLFjMjeUhoVNXNmG5UKP9jnb': {
    'private_key': 'Usfpj4Sn2UmySoYa74twCaRxDBsjLbkYjNT6mHQFuEr1utxSg6Ps',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUG8Afdg3tPVwJpiK24yKpTBaXo863kEoT': {
    'private_key': 'Ur7dzmyRuSeK6r5NdQWNpjvVpmh95eRcqKE5nVjhaGb2BzzazetC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RD3PtSPD2dHbjoWxTcyQW3sNWh1eLHnNbj': {
    'private_key': 'UtnJYDrM3graLtWKjonqvWwmrcWzKPLXApee6in6KiuBkhe65gYJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTHeMqQYXKYVp6rWm4qfwkNuD2CNCBakAq': {
    'private_key': 'UxKhyMUSGbp2cBLPLrwyFGvZKQgVadXXmfnZRjTDW4iq5hRYhT4b',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWLWN5k8oUEWC269qWKeDx7X4MFjvZ7PW6': {
    'private_key': 'UpPrWhhT7TB7KVuoXYFWnFCF5nUbXTLrKfdzY69GmvQmqQd2MhGC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RY4KpDXAvW9Eb7BEWb5L7TfoXoymAyxZFo': {
    'private_key': 'UtPzFYHrGGk2iKU2bUK7n4Qfe7uKRn2uvtjczpP22gX3XZ4Gq79F',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9ZHSjgVVP1WAdEEr57qjNVfShnsGrQoWU': {
    'private_key': 'UrvJXbXZy3EVNiyYdaV4vbkcNNuPM1zrNY1y84vyH5KoaK7uX41p',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9Wpzi1aiGSfqBszJo9o4FRARtjqpAmGYa': {
    'private_key': 'Up6cTHuxJ11qcAvbR5nbzZ8z3K3WLxqMmjz4NvZBvRDeZ3Egs7TK',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLSbjYKTvtL5xcyzMmd9xz3EWZvQVst7Ty': {
    'private_key': 'Uuy6HfVB2ghNg7Po4EaaxBNJ48HdeW2NhUg38zUgYREXQM3CiEXY',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RU2nz3qAgqpEUpScvpyNXXJ9QM5A9oFCcS': {
    'private_key': 'Uvy9AYkeKj52oqgsz5eh3EakmeEnuaQMAUNW6cmZUc4HTLuFbn95',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFAUCyHVJbxNyvinG5UwrjghyH3DgYRQNE': {
    'private_key': 'UxWsTrMuXnXLy5z6rzjrRepcLqkqWDW1iLSwX9dC8QTEuHs9NjAe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAMCY7kbVn55AGtZbARpDc3ezL9A9WrXhh': {
    'private_key': 'UvsC1oMvcsPtPLZL3YKaRXTixHrv1dioJZVEQAZtFgxrGe2cLGCi',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRJ1aTqAMExzvV3qjcw1iN6bpBwEksu8x9': {
    'private_key': 'UtukrZF3FogH8sbch2mC9AbwokxPvsBwK12RzE8cJFyTxFJ1JoTk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQzdXFJWnR5rHJ5uuno5dkxSGqGdi17x6c': {
    'private_key': 'UsmRR36P6Y78gVL374eJ2qC5UUw9J1zVdrtqAtJM8U3ZZ8pM4SAp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RURWN7Arjx8ET9mBwcfv4gJrT14xurPV7w': {
    'private_key': 'UuDHMSTKCwr8QQNmEg3wnYDnXdwuGDo2m3seDbhkh9fQJWjpzu4Q',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBKhHiGHpJ1WSZQgBoztnVSE9xZypKY35B': {
    'private_key': 'UpTQaXepYgWeUYC41E3c5pK9cDkPwfpUMRxEBdmsfzA7WnywVYTw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCCur9jzYVEdX6jR5HrcahmpdZYFoCWRnW': {
    'private_key': 'UwuErknt1xCseorj4rX2dt4o7NXPwasuxAqoKdSF9pVnkWEgnc8n',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAyexqiAEkmPR9kxi1XUmk3dzNrff7azeq': {
    'private_key': 'UuiKchebKEYLvpen6wnQgBRtQZFXCHxpX8CyMnnvX7Wuf9378tuk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXiUqUaDwVkG9gC1E3ewGzgCcrsHQ7iZRi': {
    'private_key': 'UtYTmfGfmrG1WjP6UTFBN6pr9cvE4hJVqKJPPh8P4T5FaPd7aQ69',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXWf8fdnJSg8aXtdLXP47vcz1UMvWEdDer': {
    'private_key': 'UxLvMy8F3WnFjYMAFjVZqD83brLu84cZi9YeE54K6Dj1LZu1Gaqt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RALy8rdhYreoEmebkBNHCNUWVu1Qea4Ygu': {
    'private_key': 'UpqJkdpKdCADrFHCo44A7CDTZwcX7oaMxSuYe688ZDbMG1CuzR6d',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHjGRyxRqvr1gJoFUx8TDZ7tKcdqw8DiiN': {
    'private_key': 'Uwi7raiGyuWB4As2FagoKGCLaZxMBNYpcKqRk3JoAkc7ytnM5SSx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLVisf1AF7NZbuXPVKcMdrjbqg6zvhajFL': {
    'private_key': 'Uri1gk5KejWiUsm4qHi5wSgemEZJytzdUuUoHXiawsuAxGvEZAmQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDWmYpkVYxQAnbnPoAMHYHaBaTt55tFLvg': {
    'private_key': 'UsK2A6qR8byckfRq1Zia1euP8ikTEFxcnBBevRxo44WepikFfiLb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REhi1WnqLLR5rBFkdfwQVoK3BzxbpDP3FP': {
    'private_key': 'UpZGf1mSXfMr4w9FsYQHnmCZxchzGDe5cAX8bRqWsMBB1LkUzfx1',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RS9QqpPRuhpH5YqEFcuw5eVwQ1MF6MND4J': {
    'private_key': 'UrzQLuEFZCp6xNuLj1eTKwSp36oBPv2EVSXxVM7goXWEAsV6UEsG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWeKeHY5Dk5k1oWEc6fZEEMEQSaQQZEXwn': {
    'private_key': 'UrCGebTkXjzJ4N1xyaG1Na7n1TmCamxY2fBxTjPT2StZEjk62p13',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQ3Y5R1QcDtY3yATwiYLT8WfD6iKw63prE': {
    'private_key': 'UpQFXRCssM4V9QZFuu81c8VoJdyaoznJfNYCMu25VN2hTX2ijEPD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQrHCfC6mSef4VXV3EAFMqPbmUtRdrY54n': {
    'private_key': 'UqSh4HqWAS97HeWeeA6XZryyALC64kRtzgAtkFyJcn3qarA7iJb5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFJgXFfgwJycs4VksgvmfhAuBoxqp7Wk7w': {
    'private_key': 'UwSyW5GsDpxUWT41N612Re4EyJrTXHPnqdFYXBeGr2F9xfkXo4fR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSUhAgcCHWtfspryyEHCZnF1sJcpLhzvcJ': {
    'private_key': 'UqcQ8GSjYRcio8paz3Zpyu6WEJN5ojDz7qrt4pqrPiJHVRJwtshx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXJhTeXWxc5sciohiiLLy7j7GTvF6pnhXX': {
    'private_key': 'UsH3F9MUvs242L6HWWrUN1dXXCUmchviWgKVaGeuLsBAnZdU1chg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVDLumUsxpX5rkA25bwpZo7TRvomYU7J7n': {
    'private_key': 'Uq6ESadc5wshH7pRB3d6WowEUbzcUwd66NQhUV4nPtoLSoFy8brG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRkyHR4dCu4N2796iVPEWN8AazLdGrGM7M': {
    'private_key': 'UwieMZAwqx3BPwNvvorKKAkdhUuw3Pzg7SaoedMyndGGpx4H6afs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPWxhb23obTFjDUVKztn3vUiPcZqAbpHeG': {
    'private_key': 'Uv2uTP4wYBJhg1Wz4gHXBkkEh1wnUaC7js1fBy68FPM1TCGVQMjD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUbDhgTunNHFnCor81ZgERe96KmTDj9gPy': {
    'private_key': 'Uukjwq41ghc3EaRhj9WtLXbpgK9vLAEJo77xK7truD7euqG5R3xc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9Uh7RobEMQqb7z9rQ9T1ywEmzeThD4Fny': {
    'private_key': 'Uq3Pf9UasQZUycsdSdisBNZZ2fSxDju4epVZys7kE18rnEwtmBVD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJYdXbXetA3yH5JEkCsjuPoAKHaauVfxtb': {
    'private_key': 'UpTnuh132mRzncpiTBH6SK9nYkp52SULqHHAfptDV6drbumGFbpR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJND13YvkDy3qEQ12rFLUEYu45JBYGogM9': {
    'private_key': 'UqtgpiFNtJaxbxEFzJxav6QXZXw1oGinizAVWeJsdxWRxdPPmZ2b',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REuxQNX6fMuPazSwgvDXTyfP8i4hKW6ASs': {
    'private_key': 'UqDzhm5vqUTeGW2vRqLmofUEL7DfHmWdxSoy95QqAdzfdHQKDcjM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RM2pFTAb55EFhCH1io497Vfyvv3TGPyqUv': {
    'private_key': 'Uq31Cy9Q4ok4CjoA3nQjCN3pebQ9g8J6tkYM1nz2EDw4kGeKEfPZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLU3iJXgiJqsATvWqPkECBCQim6rJokLbM': {
    'private_key': 'UtUwRGMX3EpztZmEDkSEFESpsEMkUyXN42GBz5cTWmQGYBaRuGxC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJQFCzuqxpLvjzJLxq7aTUhbgfmsrqzv5d': {
    'private_key': 'UxJjkgGDb2Ug9aphbkUTWy1pouxCx72nmq4oNAqTQAfraxi8Vt2P',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFqagsedW2BHx4P16gpX2B5skCeTA4yPDU': {
    'private_key': 'UtnsQsDuNgPd7BkKkrthvBQsQ4MD2A3zs8Y7APuXparJ9affoWFM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX53ppbg253assbvoxhQoDL6Sg3rCsrGGa': {
    'private_key': 'Ur7pM5hVn9wX5Zv83ujckCEhQqEjrH2FQd3aWmhVP1erSYwqD1ik',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRrpzQfaWFS2ogfV5D6r8P6Ls6YUV89eUd': {
    'private_key': 'UuYEYUDQVs161ieuWmiGQU7zNDAa9bnEdFKfk3XvdxYtGQz5U54V',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RU3Ptzk89uGza1xUcqjKDBwjW5Yy6zMfW1': {
    'private_key': 'UsJoFmqj1Rtm626feC1oftvHcf9gUw39pcamvVYw4qfckqM3MMZ3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RN8Cp7AZZZiXmuk8kJTnEoz9HpXBfhPAoJ': {
    'private_key': 'UsUyd3zgpUm76YQELhCtDC9gSVxzciR8nk2kSwxLipxFNSRNnByJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPtCKNqnwKg3rHfagYQJFbXzNpDJSPf4kr': {
    'private_key': 'UsFC5pFSc7yNp2kX1g7zPt3D9E3BGPZ8cJ7soz6KXFrUU4ARs8Vh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFC3N7JshGaeJcJd5Gv7c9qZ76WQgXNrEz': {
    'private_key': 'UpK5zpNVGyd3sPEWqS9TnGUhhkHfapB6Kh8fGTaRPBEhZYPgL7XZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHS1wPmy8BeLXboSf44mhQmUVsp2vQoqZD': {
    'private_key': 'Uw6rhpT2v9bfs4VCz3EmRWYmjhpqnhne7c4d4rJ4huGZ1XEi3jzH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REZ6asqaJiz32v3BummxHn2pkp8zkLS9sC': {
    'private_key': 'UuW7iRuv3w2uANu24YQ7MkmZmCYCaYJRXdDbzuwiQ2SeDxF9hML8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPmV6htsmEiafdWTHwYEiZ6WLqGNRnGJaK': {
    'private_key': 'Usjy52jDLi4f1L96sJhtZy9zMvsgHPxqiwxDGhgBRQUm5D9Y6eER',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKYjJErJizhNmoDpksWdUpNVT9imk3wMAJ': {
    'private_key': 'Uw4nm7psSLMvJaFvnXJ6Lem413NWb4VEGbJfbSVHoqJ8LiWDsUuJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJVpFq5EFErm7KdyDFHu9D2bfx68U169Bm': {
    'private_key': 'UrM4ZkkjB1ERUWVcRu1tHLpyyR9azuGbYmZgMDFyp2xUmttKow3Q',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLV43VnmFvbjXGRY4qXtMXcBeEgLxD98zx': {
    'private_key': 'Ut2onPTcwroWFqXKTmMh5uYoCy4xG1k2Lp4h367tgUnCfnUkP1AE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL8tfyMevqF9PmB1XHb9p33vDQJRcLnZiv': {
    'private_key': 'UrfrBZKBKnqdSTNwt7JdQ96eaWBrSEupRPTGoMw3VSuHQrPgBV3v',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJJuMs5KntvPQv9yQuWwk6rCDsJEvQx4hx': {
    'private_key': 'Uqe8kGZc9atHwWwzmtEna4ansuU6m7M4tPTjXFqLGzX13zhgy3gM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJZ9hBkJRxAKRkErWK1QSQJweeeMvcGxbc': {
    'private_key': 'UvXdAHB63aHLnqyHBswrCDghmmZ3cQfPPfC3wZmKbbm5qRVMBHqR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPS5zxDTzQtMa6rwQKwzLrFaJGjgRczt3D': {
    'private_key': 'UvCQrNv4M3mHhBjruz4QUaxjhFxEuddA1edfgPDM4Us3FXZHPY7E',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RA7ZQcwjeiVNAnKYCwn7yx4Gd217KbV68E': {
    'private_key': 'UsRDtTqkGccdbUmbKGUKyYqB8Dq8845R9y24NAYfRKSX3djRLGhD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSDoLKD6NTG36Viri717fZMrfiBejpwxhH': {
    'private_key': 'UrgyuQkeSDCeNg31vFZLKsqUXLcWbijvrWa5eRKFowEyCC87qhRv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RS5yGG9owG4m5AWmmEox6VRZ3RhykW173D': {
    'private_key': 'Urt9eXtxw5dwqPXsuvdXmGQfABTFegjYpk8oYGFbWtn3AEGF8MMq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVSDJzGMxFL9pxQTskbAUkarsa69GjKQ5e': {
    'private_key': 'Uv3NUjm1wSa77Z1MyiqL22tdqFzNhvHVsqMoyAWsCV2Mmn5vFjTD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGLwnB49JoQCvgUDRWcEEk5m4yYDnB7sDA': {
    'private_key': 'UwqihpWrxcDFPu955czhGzc1zHT1m3gQ25nvsr1ZuV57C9xuo5Fq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDxHWHL4mtt2zAL14ATg19YTNxdbnjAgv4': {
    'private_key': 'Upo2hpTDxAkePNxHfwrpEQXfwNP4iizszGiW1PN7se5rq3WuMCwJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHgYvC7bRMBeDzeucSgwCgFDZ8uVErFoJG': {
    'private_key': 'UsVY6WTQKbJVe5VYhQhr6Zyu5i9vv1FhEwMkfAQ1yBQDZpuZggef',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSXRAsaCL9hvpXjCmXPRsbF9NZgvzHcRYU': {
    'private_key': 'UpVjG9MfTPZNsV8ByZZh4sgRcCDJvNnhK2EqYKkpHEQ2NqirHTPp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RF2UogpuB453SmXcgjmC46kArzCMG1qPX4': {
    'private_key': 'UvZJcrmnrLSJHWByrrBQqh3heQ4Wb7PJt3s9Jux3EFNYHqiAzgTk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9s6GHviyBxZq6e13G1j6f2431nbkGmSk7': {
    'private_key': 'UwbUVwpTvAm8ubQFJavYJJyq2jTf4kuGe759mD1jvxY9LSt7Fc7a',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLoGtMzuze4VhL3L4DjDxQss9Nr23zqjeu': {
    'private_key': 'UrsmtUCofsSzcYjKiWBjPVoaDdwMSewBHQqqQEhMERsjB264NcKP',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFeEqzi9t9ceZjtXLkgtJMXazu6p724jdX': {
    'private_key': 'Uq7CHwn4rE8H8ozzwvS8SQqBZWCoPQv7xbpT2QHTK5uzf1fiRxJm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUQaMBo7JU9w36tiZZvTUqaZNJmTVR6nXX': {
    'private_key': 'UwqKtM8dtFdfw1FrDJvL78NxVTPFUFPQMrzqcR8pecCYPCPMjt5o',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRkx63ftnZCFDqU8rrQ62Scut3eX5U7grm': {
    'private_key': 'UuTDBcZEBSEUQgLFF3jQt4Nnt4XUjWj4VSsDA98wHLSsVNcqsmeA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPxXjnVTDi8ymbAsxBWeryNy7H5WdtMEcp': {
    'private_key': 'Uppnkb5mXvgLqAqbEKpaCPdZhzNB3QjyrHEcC1gj7Hkjkcb9V3cN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJxesPmfPQiUbLPuTSFTyWJwAZZz5RATTm': {
    'private_key': 'UqXEiGUZT3mBQgMsYK97SYFHfdgesrwNhGatk1iFRKUiYVC1qNrs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJ4eb4tGZQJirVKwEr8PZi1UZQcwSW6EmN': {
    'private_key': 'UwHaUq8pRBUby6JMNt2VL4Nfuo6zyxLJg4FN1JgCVd7pHTPBvcdk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRTq6joFvhRdk1BgLTPyz9jgEyKQ5zjtUX': {
    'private_key': 'UqKX1yoypvkivs9XNAEkcNkKVccjTdt5QAGEtiHTX6GRLXj4uBPA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGcCnghYPVvq8LkXEFKmgKKuUWzJWQwzdq': {
    'private_key': 'UuUuPxhY7rQib1x3FScLbwdCuy1qm1vigXXKVmRyB5Ep3ukqEz3R',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWiL5EXJHjkDJDsgJWMdvRbwrpzy7BfL7t': {
    'private_key': 'UpUWDtJpWxqApf31X4oNMSFLyWPfoXqhwAgqq2vzPc4ocYfVedbp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUz5znvs4F4af2ufiWhGhC6uDz3KhUsNyu': {
    'private_key': 'UsnXQhWRcR2zpptSEYDAzEFKdjE62zQSgtRkPDT1wLA8R5UH1NMG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXH2g88EZJP7doiovVYyaKaR3PDK2EqVVc': {
    'private_key': 'UtwAyp2AKXSQ9Kq8UAVUyrgGUgxpGJvc75dmWcb7w6VKFVfFm2Zt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVZtBpLNhumJGiWjq6kQbPNTSBFEoexb2n': {
    'private_key': 'Uw6RUEVkodU4Gyn6j9aoNgMKiwHaLVemGMeuk2KhwbWFGoSgTMAn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVR9mscqmnpDxBfo4UkbSu2PoTrZBU3X1a': {
    'private_key': 'Uu6BfVwYn9eUhsVnJpCsZ8jZo2L4p1jg5XKSvSQfNq43CxDMr4Fy',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGqFjYnQTNbY2MY9gbMZcAxx9zKaJtgHXP': {
    'private_key': 'UuX7dzLPCAWbNsbiKWmDgaciYvgoPLYDE3HrgeY22NqehkBsiGqr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDJwK8oVTMhQN9DcrQoCES5zmVZHedxqnW': {
    'private_key': 'UqJgSGZXNCTkW9kzqjTR4HP7gjXhnf2HgCNTuie23EVSiUCqdexm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTS7oJeSv7VUkZftiv2JNbQ7U4ii1e4ADn': {
    'private_key': 'UtPNx7bmff48MWoWuQXPg9TU2ZRV4R6cHqfUKfYCjJnVNiDgwhTM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLStmoUZkUfrr6irtM8Qih5V6sfDvmmRvd': {
    'private_key': 'UtA3FBs8RCzAAQj3Vvyp8AFfnjx5QEdvW8QbNiQ77oVxP5UrHLXd',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVdDfnXxXphRzC64zidz3u5uw6Kq4ghbjA': {
    'private_key': 'UqsbVRowiR2Kfgm4z9UtnGa9bqB52jyB7Rdzy39L32bt3fv35Yr8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTaGBfHua9GwXNzZNWvrPmH3xRxgzWNZZe': {
    'private_key': 'UwCv8SV9YyCYKaxfHQ3KQZv8Q4Qh1peEL8BrkuK5k5LXSmTf7mDJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RANvv7USsCZXwHu6CN9SNVQktJF92mKuBU': {
    'private_key': 'Uv6GGwuLkKjoXZwvdiYMVeYHaH9CDhSNSyuvdtQ9JEuYNUYgLNJL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RE6isnSavs7tHkzSm4Gt5Hik3pWbi5URTL': {
    'private_key': 'UwMTAnDm7E8DD8KPEJ9kjYQJbAeJofZoWniG7Fin5YwD4aiU9nfV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSSLV1Rqaas5HAAySKYXRtDfS2p2PA2rM3': {
    'private_key': 'Us8f7epDqg1e3dtHbVPE7aMAcpT4p1jSqTGnCv9SxcBVJT1L8zGW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNHUHNdzLs8x52nCF26YcyNA1snZYdTt1U': {
    'private_key': 'UvUpCCQTF915YjrffGveK3zGWn9juL2jUf54DYa2p8BcBK29ZLvH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBjg2FDdYPA1vrqqc4vxRkrmjsgks3KYAe': {
    'private_key': 'UqHB5C9rSLiKQsgG1nUCtp7zue3vDS7UmrYzZgDiPb8vCFjazi1N',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVv3SGfUf6cWBG7uhpZY3XLU3DdA7JUUNp': {
    'private_key': 'Ur1NwVCTGvQTtiqsUkJbihcq41jbDoqd87UiU4YJ5y5X3UyNBwd7',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPopcquv2KP6k9GPMhAGncoUicGMivyTtD': {
    'private_key': 'Usv4vLaxVC2c3HtGCZXZ9ocCKdJHzpz9M6C9n1otH2yqF7p67rx3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYK88XRvm5svRC94G4LnSJoM5WjZPiuXqU': {
    'private_key': 'Utd3VLQKR2w6hYDa1NFXLGxdZqEEzPECjgK7uZ8D2z16zxT97L6P',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RN4CHqoqWu2WmW99CCtUkqaVVUbtEuioTv': {
    'private_key': 'UsKSYbgE8Awawpk6EkaRNeTgTTRrQDp2EpXDLenGVGjVFKQz91tC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RD3SKZ92T2Nv8ZNoXekEBLWcpDVoWYhmQB': {
    'private_key': 'UqgSqxfWFkeyjj6KH7CkK2jNvT2iB6ig8UaGLEgmZMQXPu3KxFQt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWGvmb4njgtFqDpNtjk3Y9C1AyojRNT8q1': {
    'private_key': 'UwCfphHmfEk3EmbxCNeMupo7rGSsqHb6v8piYxKFDfg1M3PkS7h3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQNaWR5hZrD1c1F9ynEJ4MjNsvSVpAr4QA': {
    'private_key': 'UwwFr2wDQN3ZY7GJzGALptgUnfFTynHYp51HSjaDFmKymJfyqqTp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMZPXyUqesbPTndWSV5UvYdjtmc6RD1Dsq': {
    'private_key': 'Uvm2THLdki8TaDxz6J2NqZmXnG4W6okuapr3PyGjpuVfXM5SLRu9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RA11XHpSEshXrkVZDGkDNcvpHRQSJNvanr': {
    'private_key': 'UuJy9kmURU3kB2WjDFf9LsjbPwg1c53pUffEnBbrY95SruypJqiT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RG4ZRzcwt5bXiGqndr9vPWMhjG71DqymmC': {
    'private_key': 'Uv6mtk5XkNzfc2QTnuJThQp3yWZuR6TwjXwt5BBX91qRZL7S6r26',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUeHP2bdaTABCQn1m33YtE8YqaVZ5hc7NM': {
    'private_key': 'UuiZga6FSSwdyZDMYhM3EdUU2Ry6sUBUwzpEEUmsPjnAYzoCSi1u',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJdrmjaZ6TG7JcUVbHgWYz1FjFzbJxpM9d': {
    'private_key': 'UtYJJ1HhHgK2mjpYtEJe6kD72QD8d2TDEV8E7JD9yU6tF8AzYoue',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RU2rdb3wvXANgTfP6zKWMU4nbAj2nJWC9F': {
    'private_key': 'Uv8zjaZYM8657CcFkJB4Qwr6bPVXP5LcBUoAdUEFs3dpAMpSxJcw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX8SW6u92iKbDoivVV3DzT78AoNbxG3zTY': {
    'private_key': 'Uu5cBdKj6MQqHemtLtR4vDv4hXPfL5gLSnTGdRvrBVvxm67Smr9R',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLjyUuz16aHDCgmaK3LyKBjTrB6DEsa8Ns': {
    'private_key': 'UqsQYAEdAETY9icdTQ6ojV1Rzn22uJ68ibmfQMrTLn93s9LrsGrc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RM4SENRXmkRLmBaNN3ASGaxLFXKZVqcqik': {
    'private_key': 'UtiPd5NndtFPgmTGaHVDFPh29LAfE18swj4tbx3pnU4sYqzc4nLA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFP7N54MQFQEiNhj2v3wC3VvzhGvpcawq7': {
    'private_key': 'UsF76289r3vUF9eqRqFbrvFKMAQz2jWAAPjjxrc2NAnXhFzMhStt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDY4mktBdgQw8vDbpYBWC48Vgwia2C4XM4': {
    'private_key': 'UsAqKofkJw5a5ZGQzirkjX5oG2zdm7Pn4wKYB2No7mBzshX8RkyT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RD4bEjNbLzw6e6AN4nfpsyqRGC38yHmjRT': {
    'private_key': 'UubymcbiLQJ2wvHry7WFTjrvRXNUUwsLHRc9C1wY1smiT9vSCKPK',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKDtkJCj4YeJLo8pQx6FfMRWZTs17GuP4Z': {
    'private_key': 'UpjQVFj8ci4WN87bpfP8JykkH3TKpbxRti1TbUuACULosnbKBZu5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDZRNWMGii1LFvxfG8TjoQLsL3W6qkoCZH': {
    'private_key': 'UtNELB2pVgGM4kiKiVtaK8mTiqg9DbXNP6ujqcoTpq31hQh6qT5Q',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMBXzs7QmnNMJvNJettEhh3yw8wVb6fRvg': {
    'private_key': 'Uso245vbbteKwyyPz9ykAQmXGF3gqVUdSfrDxfua4WRcHfstAPnc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFfsPE3J7kvxnkoVQrGQrf2CwBK7NGA5a6': {
    'private_key': 'UsDXZ4bnQe1pCqvxqvyNZr4pxTsa8mGUeAJkeqZ2dXR6fUhJtF27',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REpVpqXfbUD7c4LBHjMQhzQJqnADEekQyn': {
    'private_key': 'Uq46YcrRdY7G9HKTU3fTWqYRPAvqaB7ajhU2Gk4MkiZ4Jcukir6W',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWsVn5vzTvEj6ErhhGLax69KHDc1Mf7usG': {
    'private_key': 'UwdB2xT6mpxP7eJo2SQkjrDvT11basx2ybNSGpQdZgK6PDjCQUA6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFkiGFMD4tgzLGB6J92r8ngGo9ZbHFBByy': {
    'private_key': 'UvCoJDUBn2JHY6cSkBMVa4yaPsxWYLFQ63rgfHjJZ6Ej8Dau3d1g',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWdJSGYHfRVBreQ7i9gQyZr4sWjQXPYLbZ': {
    'private_key': 'UthtKv64iY3viUkKnvw6pwFRyizHSij1vPKR71uYfhHSC4HWBPik',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGiEZPDpT7jE4dFYQ5cerL7gZwX9ssHx9T': {
    'private_key': 'UwQWeMWbKwmqvyoTdgEFxcXZtQ7HRkGrVc9WtrnQbRNJ68YsiBaE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQi9vU5wm1uYuehSkY8NpUSjS2w7eYiYDD': {
    'private_key': 'UpNXHno9Z6gvemsEojj9kUKfuxSNFeXZnP261eR7HrgeV6wH9dkU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRg2o9P5gu5NAfdRHKtgdLyxvA9ATMxMNZ': {
    'private_key': 'Ux4mAdUVFaD1j8bEPm3BBxa1opcseS9GzSHzfRaDWf862BdYai33',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQ6evbLPXgqFXzGvvPEmbrcqtspa3iXwut': {
    'private_key': 'Ux8mVJXqmW74ApwuMUpWV97cGvF7Uvmfo436pooa4ZrZUjScEXMt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RS7vbK3VyYo32X75AE3XYhTYYA3ghxA7bU': {
    'private_key': 'UtZ8YpKJFy7wj5tqo5s6K4sJfuzYUP6AQiq5T94qLTzde4m6nmmA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLWd9bhRebws7FC96KvfHMuQ7s5kz4MFky': {
    'private_key': 'UqSCocYuNPwgL2jBX83rbRUbEHZCv9QTncRD2gbdJ4oYRAoRNYMc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQwm5fa3xay9YPgj4mfn46waUKay52hnt1': {
    'private_key': 'UvGkJcucGfeCV8cPWC4D1FzKupAS8CytwzWZUj2wSCurBLnY6uXd',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX44uRvbQ3ZuQrf6AateS2fRZSxHHy8YGm': {
    'private_key': 'UtsesqSjXH5UhyepKJNPasMUURWmrTPJCPF7X2oq1BCuxjmDsxu2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RR2MW2Cm2bay5FPRgQeZ1PCPpkLD5ELsjT': {
    'private_key': 'UszGE9ovoSPv3vroRrwP41tqzoBmwCXy7T1p9QyhCVnNHuAqf5TR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRRgbKGDAEtXYUPFyJ6vftGrhh56etwPG7': {
    'private_key': 'Uwgt2iiTTtmVjeJYZ4BYjRZdo3WXZpQ3i1go36Lbn4Pp79BXN8Qo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBA8gfRbEBmwztkfHSiew4MfpRdecYRD9a': {
    'private_key': 'UwY1iFYSTD77oDkYG7cYmYHFBNnFi6jXpYBy23V1pqfSnnCu1HyF',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNMcxp5kQDKPsotJSefeApre8vD12SRVHn': {
    'private_key': 'UvT6DVEuRfRH7q8qqJHoSL3q7SD4vGt3vjtpBym9G84LMN2jzMp9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RD2MR7NBo18bScVxbokgzGEenDTi66dCaH': {
    'private_key': 'UqinBFte1jsb9UpCHLaPCCXxHpiw7vNHzCeGskZffPr4n4MCFiqH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFz43w5YseZvZJBZkq3dp5ku4Sa8JBtiTq': {
    'private_key': 'UxBV7u65Y3KWvif549yEqU12iui6DYMKdibDGmNNnr3NkYDPgvNL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJfzmAA2fd2jNfaHfhCZc8XKWDfocJ1Eo3': {
    'private_key': 'Uvo6Rd7dcJo6LYC6DqFTVYZ1LjhV6J62urTGg2GgA18mrZsWXe6L',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REfRQaABMWkFunmgnhNizMSmjrh287mLa7': {
    'private_key': 'UsHpuzstTamsPmFa9cN4CjAMgZiw6KpEaqx3GxF4WSsvjozuaudN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REhhWD6S4cmugrch5c4yo5m6Dh2Wk3zZYa': {
    'private_key': 'Uqk4dYifJpu9WWaQ7gDWjqHh3CL4mtAgV4XsLgij7sjHbDZkjxtv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBZHkzH2uJCyfDKyvnvg15EhP18CxScPj8': {
    'private_key': 'UuLVFDSt7zg3gibBcd7LhQJjZuKCX6P4kobf5DN3KKh8KfeX1XGG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRhxqwY3dzijcgu3iTvB7aCx5a6L24sxn1': {
    'private_key': 'UpvjHdGKEw36qL6m1zsZWxfi54vUWFw5AjurjwDGwYQJFj6hx7ex',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWHY2n7frU38wpDnCSJYeGNWS9fsZPRf2P': {
    'private_key': 'Uwp1QB3qxQCyiM7RqUiau7s4Xy3MeM2kBPuwuMMbtNAWh9eA7DJm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWJh4JhubVxYxDPKXJhVBgqifHnVFDC8Cp': {
    'private_key': 'Uq84eToVXbh7RKyHt6YmjzanjfGztvxnRf5LK1tKYDgkGv5VBQ81',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSrDTSCUVisuYaowkRYpanYZa94YDreLcG': {
    'private_key': 'UxV24ecb3sYGeSzkpqMhWSygA3zJKD618VLKdGJ9dtfWqJDYTXvf',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRrPjMtAxUTqomFPweZ8xgbV8a7YE6mYNJ': {
    'private_key': 'UwKHaDesBhoiHn4sjPX5rdCP4BX89bnbDRwy5ZXHdc2eU65EhAnV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RS6B9HPX9aiLhCubPnarS22PcrYgD5Wqb8': {
    'private_key': 'Uq7Kk2sqEYxZHnMfdTdZAFQ9LtTaY1aqBCijYyiBAd734v2G2Rfe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAgT5Je9vQUYjdPUqsoXe1DMqNHQpYrZYs': {
    'private_key': 'UqgoVna4jrWir1F3oNsSKNhGuP8Z5PZiPjBMh6oTDuogSJhfTFPp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL6uXGJgQE2VHwWurcaJi24boVjMtfZUeq': {
    'private_key': 'Uq3CHT23aNZrwoeDFfoMZKRAs6xqvZVgrE8No4Kd8kPgTVFV4D8s',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQ8LrcMQrX287wgHUGSp8NWKtuxN85qFaH': {
    'private_key': 'Ur39kUCn2G77DDSQgjKVD91frK4yckv4J4tu6mKAgpwxLfXECN42',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHMi5uWqUnTjZoFJNDJPVanD49yqxMzHim': {
    'private_key': 'UskQpxNtY2kwj9QUmYKDtbEB4mwWD5ku3xVGqRG1XCgDqRVTqVTN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAWUhzqFeQukfaNcXKD1GBVinFHkS2UA8y': {
    'private_key': 'Ut6TqTqKJsCDn9RS4vJx6jBkicFkdU7wSd1ncWDxhndhcSTCM7qB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSyEWcnxBJnSLUHBHj4D3LHgAX4YHCtzwe': {
    'private_key': 'UxHCHWpqnowpVdcUMcqaYaSTvRVwmwrKP4YzA23CNA9G3kF8ZW3D',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMr2r2H3Uxsq2Q3ubLnB9cuHLCwk8SRvmo': {
    'private_key': 'UxJUMwBChN1HrvNVdeP5p2RtKe47MhtXaNcyFbgHeF3natStmGnW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKGS6WucsjbE3DRe3kZrwg8hAE2K2jrPeK': {
    'private_key': 'UtFAeEs2K3gjQMpRhQGsRwsBskCaLYtErHbHFw3B8y1FURbZ8xww',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPHnXhYD3qQkn3QKkHhRHsRn88wXQXDHRr': {
    'private_key': 'UtBHbuKMoPE47H5RJ6Y4LngNtDzZxVpqXef1q2K51GjjTXvFoAis',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLSP8JweRVZLH6RkHSUYBmUeKXXfUzYzkm': {
    'private_key': 'UsVint5FAg2i2NowxnsH1JSZaSYFfc47ZF6CbBwAoeWz1Mor8Z8Y',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RV36Z3kys6bcB3PTTm9vZGqSGB1kbJM2C5': {
    'private_key': 'UxEi1ejyG1PEjDC8HhDGkAjJZro56R1CkVsfqV2zxegSLx59aKRa',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9p4BzqfueEpsC6JimteUfHYArX6JJy3by': {
    'private_key': 'UtCjtP5SnXsMEXsrBQGFnBhEX3XSDZpsAcbmH6qMqtkwXBjWNdPb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUwRdf1n3JnZzdv4mVS7LDF1o24XoNL9ne': {
    'private_key': 'UsxTmXxm5TAGFmt2X6LuTQRFcw3T4NVJaPi6kctV5pWPwd6hKyDm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUfkF8G7VkwG28kGnsWpCtfzYoMLvVHPph': {
    'private_key': 'UvdCu7Nm8NbjVUAx6jizucLzF58EvAWUc6nnXaYWeFKvNasFZ9ua',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAimLeRT2KB4gnMSp7WntCnsUBQZWaZN9P': {
    'private_key': 'Us9WueQ1oQRfNrbXmZpXCj3A1ZSJFBYZ2RBSpKsabTdeauYpbV6s',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVp5F4kbhWAWfbvgawp8VPooLsWc7EEvWG': {
    'private_key': 'UsPdRaWfuzuYtDKJS7n5kyyQeSwLraBCwfVEwR4jj9foitPneZAp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RT6QJVFHwy46YQF8u3RDKGnzD5DCNYV4Xt': {
    'private_key': 'UupABaQT4uRKKs7mXzXRL7tjqzL3Qx9t6nM1EDdgNwsrdUV2CLcg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSYwjtsjiCn2Z2r3vP4kSrig3SJogYJyRw': {
    'private_key': 'Ux15xQ3CYYYA87wtzzzn3oJ6fbHjBgTbocJJg5adJWp57YzScr5n',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REmfnjtHSbGvVqUPUHXxgWRyX8tNoL5Bmb': {
    'private_key': 'UthNvuYyqM9Pv66i3jh8C3ybrTSXgyQd8rMJHzxnTfYGCGR1nJHb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDPskCz4LqAuv4WbvhQGiVw9ai2NAbKiTG': {
    'private_key': 'UrWAgqpyQDpxMyJ8ZwrT6tKqTvPrcwuq1XaZ4yFKrUmWiR8C94Zz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RB2pUKfZZaLaJfYSuXBiqDDdJrtRLjrnf6': {
    'private_key': 'UsU2bfEw2zezAR6ykPigKT5PfDCriTWkoYoeMjZWYt6LPFNi1z7D',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX5z6W18SxL2zegQNBWuoGEdSpg4DEoiAU': {
    'private_key': 'UsLdnJJtYBToHvP74fCVzTQTzNx8jQmFZwzMZFY9FHspxZ346Ji1',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVfmz5zgQFdxWJmsD6CFx1ZRumq3DmPmwM': {
    'private_key': 'Ur2S53Uh5dmJAyjxC8zGTJxpKEJ9GCFvzZ6xn8tKaYm2MbttgrC1',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJv62TGM581bZbYhkmCGbj4AZjBsnCY8wG': {
    'private_key': 'Ur4FxnYNmoA5pYNgMrrDkh9tDiRgrxSLdFGAgdLXxbYEAarjUT3Y',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJBrb3VLKmxpj9EkyB1z5wnaUcVDCXssAn': {
    'private_key': 'UvMzvvpvWA5azUevtzDGC5UkGRonEsoxEnUUMs57iLCFpQxFSHv4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVJRZ4V9ZspHJezYKWi8HXhURZ7Bq6W2rW': {
    'private_key': 'UxTfBrrwJ9x7K9bfk3Gjiz14QDfAxjFWokuF7bzfbMMFnNsd3xeZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRsEE7Puyph1XXroyi1Hp9HkHArhecnDRv': {
    'private_key': 'Us8hzMxrQHyH2ck3DuC89CPjzhRiLfqVhutjSAGZmj4CXfNnD1bg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RM6gnMAS8KpnWSvJ4gqrV1XpyFeTBzjub6': {
    'private_key': 'Uu5uAnyZxwrrepPHirSRiZBGUFTLUTaoNzemJXE3WpjjZcHoh9wV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLwnhdMXkWsnL3gRfkM6UQYdBv3qseyWA6': {
    'private_key': 'UwobaUvU1y7NKYND6PduofHv2JxHs1447MU7FAff7U866gPjuNDu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQEHJB9fAHaKCUDSpePa6bUffT5xdzQDC6': {
    'private_key': 'UsoL77jQEcxMGdGsTtBCnAMGY4hYpQXghPbyUnHichVCFzZup7h4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJZ7BWDpiHtjv2Y4steiDDfYgTLBwh1D1z': {
    'private_key': 'UwX8PiqGZfj6eieUWRBkzdsYDuYqUsutrQE5xgdc4n1m4wcBVMyA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDto6NZdHe7iL9QnfQQ27Ydtm2meU3dHVB': {
    'private_key': 'Uv8FsvtNu8WVPsPjVHNAm9YchWdUyWn3urnrYofstxg9r6gACdqc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAcd8TMVFjkWs5sE7Ci2ZgcTe6UCJGTEVT': {
    'private_key': 'Upjg3yFt4SxsRT3EbxcyWJRRHxGJAQCevpjT1qKRp1ZWLfLSBfeL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDz639s2dRTeCDHe7qdKtH6djFn5N7uDfA': {
    'private_key': 'UtXuEnPYL1zwaAMgHHdd4V2rPNzPRM4cDpFT4JXS7CQ1p91KEh9d',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWwNqSA2LHHGaND57Ena1QvqSRj626n5UU': {
    'private_key': 'UranqSXkeBABtoGuLJs4bkRYUiMZHHtJP64YhEuUnUDQb7qJtJVD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAJnrKSckdzme6kH5vBrSd9mEsrfpZzkLU': {
    'private_key': 'UrM1kN9ckesBdMou1E1fgrQDqdGwCtw4HtSLrXEGrEsYZPkx7rpt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLKXTUf1eP2w8VpLfr3HiCAgndGm9brUQX': {
    'private_key': 'UpKA3wectkA9pwayjmCN7NPBxwTGudPj7BNgstspEtd9iFQMK9sM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLpKxNPEfM35fyatEVYwjo2Btw8ewtueBJ': {
    'private_key': 'UtkChzJGpY2jURc3WijGbz9uojtXB86PKgUxTkQcC4LNLvRaKL9q',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RT9tZ9ppkgG8UMg7hVphYpYWfofZNjobM9': {
    'private_key': 'UrfQkeqF4GufoqPFpEkj95HUryt9DQQx66wSgbQQkHnD2Jm1Wcpz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUHm5EPT3oTAv8skcV7gAJnzt6gKezA82P': {
    'private_key': 'UvYMvXbwaxVRrsP26N2Nz4gWEzVy2gJQjqHkgMGJz4nrj4QNpWwt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL7tJmW6rM2MvikRnS3vGBUDEJaGmscHfj': {
    'private_key': 'UvGZm3JqPskfWXYZ1xA7hSjsohgWMyfncUqRY6d3pn1Z47J1kNMm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMjTmTQBMrmVNSmZ22Mkf4ADoRwnLNkuUD': {
    'private_key': 'UwhJHZE55dakecZx9xjfnMou5VujsqDYdFrdDXcvP4NQnppPUSHW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RE5oHCtFKvKvD47J41PyuvbdUAFJfULyCK': {
    'private_key': 'UvERdqbRSJW39M37pkec3d6JqNhYtKG8ZUtfuPkAdMjYj9M1wLNH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RADXZyc6NmqzWQGKnFzGDCBuKxdEjc4qm8': {
    'private_key': 'UtsUUNFBFxtFyiwcdAUdJgqv77X8zosa42QbrgPPTnuuPuYCxjiR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUKVgyBwSkBaYSftsfYGzFBKBRrt3v5GJF': {
    'private_key': 'UspTdUYLJaLcBX1xgDokaqNn7fhVRgvQCAnSutWRWwp4wnZVvCEA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCZ621vb2TPQ9xpwtPo4Cnf8bRbQG3RGFM': {
    'private_key': 'UwUHFDRNtcDeCui7K7Q3iEkQYzNG9mUorLq1KGPURtxc8WmmXRxs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXytavPsTFAFY6afEzqsLQf65TirrzpVB6': {
    'private_key': 'Uph2w31yVP6HEfSRkSX4ek6mRswbyS4Xt5tWZzD7E34AUw7ippR1',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKtBFpvMVbpMT25bgcLLA9Ek1M2V4KVDeP': {
    'private_key': 'UtRXpDYD9eUpsaRZ5R47Y7H6cn3DrWn1mQchpDpp1yLswrDmmMUs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RF52oCuFyQdB6bPsU7AEN2BF3kiLY1r1Wa': {
    'private_key': 'Uppfd9VS65xqRQPVZefcJ74gx2z8TNGN3nGdFzZcGKFYdMVndXhw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNwAiK3x3XXrqEb8AEW6zRXCJMSEw8tcPX': {
    'private_key': 'Uwtxb5ssTk6o6jKQGFGgoFJQWo29vB1THLgci1N4HPfMt2ezwDWx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RP3ZUnYvebAuw7FdXN3YByT4ouJX733B8Z': {
    'private_key': 'UxXCB5tYFcNKjaonABwM8B9KRvmAzHuL3Gmn1jn7osXDzi97VYeL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9L4jgYgMH5THDmhUcLYVmB4kyLxh1VWhD': {
    'private_key': 'UwVhfjWsp4QvrDcB2sqfW2LueAKtVyEag8Pd1LA2kp1yqEu16brK',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSuBXBdJ9A1RJ7DFerHFV8z6pLiASvU8zT': {
    'private_key': 'UvxWid52YU4g4hDLo1cHfdtC6EebZWgtiP62XysB7XKUYANaYR16',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLEh8Rn918czr8rqENM3qcL9Kyn2SynXYX': {
    'private_key': 'UsvhGEaNMaPAy7coaBj4cRviRcbmSW2nYABEoLGNSf3htL13gZLa',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUNaYoc7z7QL7SzX54V6DfcoTdDZQXb3iE': {
    'private_key': 'UtqHWS2iqBp59jzKECvvDYjhcKGc5CY2XGWaJYNnJVRdubhimPGT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVg5R8SK26GG3Dt4U3f6hCTrXcn1YaigPJ': {
    'private_key': 'Urof3srKLTYX96zraF45mtmUmK8dTF6GiRDHqgccTPR8xXHLzQ9N',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHfjxTjp39wB9RoWhp6kBS6abmYU8WSZrS': {
    'private_key': 'UukwRGDNhQBZqRsiuYxBfnABmo9MiTsyCSKnn7GUq6pSyjFWLy6n',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWaGuRgoM9dK87WnXMkSdSFdYSgd1sAQVy': {
    'private_key': 'Ux8Gia6JoJN4PZuSoy9A68qR7HF9biiLwZLtFMhxh6f1Epft9tAq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RM1SMYRbTeGTVK6auayC5HFA8CxgrPjq1P': {
    'private_key': 'UxPLYJqQ2hhNu3X8NFySzdaBSodEztCdPCPGcdyC6SgGwcoLSeBU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBmys1CZLnD6toSmPbSzUK3eaG4tduixDb': {
    'private_key': 'UvCK4Xy76YNeQX7mZfDQ76gZzwWfaFvSmv3zqoPJQCsLdQaEQkQy',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDApaN96ohbQqCeNdTPUdKUUTX7eHtFcJi': {
    'private_key': 'UuYhUiNUy2hNZhf8LKefPhjGRjWDGjDjs5C7mhCZB1rTpKhHcGXd',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBT6vzpiXGGTQSY7qzVEf1LP1ymag7mN8b': {
    'private_key': 'Uw5Udu5DdtzPP998DwY5g76oF5VYTkyuBbAmd6FNbDf6uyVSyR92',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSYtF31dQkVE2FgfCHfiEEZfK6aPybqn4e': {
    'private_key': 'Uw1hKShf2VGqTXZXax1Arz2oG6zY2Ht6JY4zNkfYjC46thbqQrmT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXXMvp1fUzZQAnhE1kStqFLEnCCNZTdUZL': {
    'private_key': 'UuQXQp8T9ktHvFjLLqErdF2ew5rSPpkyYkMrzNBkHznEM724ao66',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJzAQJYmHuUV1DnCjuTBSCod6mAYahneYd': {
    'private_key': 'Uu3NqzQKssEqrrZLNbaGSfFeA44UxTTPao7fm3PiYipnyWx2JxB6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKU7X3aUDXN3eS93GendSE774pstgiYYS3': {
    'private_key': 'Up9DbEup5QBZon2FGSviPNdsE6k9pkdAJGmnLexaQm4UsNyrzRX6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSkKZFAZVmgkQNyhoZGEYUCD9GqRnfmrcr': {
    'private_key': 'UrxrydR9W6iYvmPQTMw83kmjaUj4KAAxhCESJk3ikEsALZFySvQV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNENdbg1rb3vBqyb4Xy1De7L3BrdQtEy4p': {
    'private_key': 'UsQFPdDciMscXXKkq3LcmCHtEoCkpWtwffhft3NriDkhs5WrEyEh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKKHBChvzYTkmeZa63bKJjKHAUxXL8fbVp': {
    'private_key': 'UvSPyjqRwKmzppZtU9iV1zYCjAkss3oH5xEo6nCeJpQsfThcMcaV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKMwpr6oqSekbaif3W8nvVNMScG8hXXgzn': {
    'private_key': 'UuX7wyHRUUyVLbiFFndcmPWbKwT8TuYHszAbVPLC46qDUYKCiKZQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPN9aj4FHaFfCuSkysXi6MzgNVv5TCTs2Z': {
    'private_key': 'Uu7no9PqjskS4N4MkJm7UsJErwZW6e5W6iYNvjThuzG1tZ6UsEN9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RK5vK2JGu3toEhGLSUWN3TSodgbbefNfEo': {
    'private_key': 'Ux9viQbUgSUuQgX7sEG2Bom2JGvoZZ4yCM6GNX9yBUGCEUJAkDLL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RP3DpR9dTvEfh5X2uW1aKjornR6eF29p5e': {
    'private_key': 'Uq9Knjmw5GTuFJ4vs6kdx1JKFnHqzpZTeDhV7jkJ1h3R1usTYPGq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVNkSAvYZSDiczDUGaqUQQd7sedwhSqDK5': {
    'private_key': 'UueG4PKzBAJfKCYQc2M8v7a8p6A2UmbwjUdcwZxmAwbwao3uLd1w',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RV45Xntj9qorNuXV4XJqw48JTZr6j24Nb6': {
    'private_key': 'Uuzrn548faM89ZS1J84TYk1bo2PcuU84j3aFr7U4GrJsXU72E7Vn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWGnFPM7kzeG7hNfPKHZ4eHZPAxQGA7Bth': {
    'private_key': 'UshG48d2HPfsuZDWJQL8u32SU34m8srud9SHVAtE41Sn9G7BjEJ4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RR4zWCTFxhFmXawx9QvpgKJNRqLhmjpWuf': {
    'private_key': 'UtkGwNvvP3GwHaF6ttixyFpScHmFZqKAUiBTLfLXvBHFZhM9EE3n',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9y4uZmbYcPQPoenRYKLL58ZDG9mjjKzZG': {
    'private_key': 'UtsoVeZYgz3J3VTp1fKeCBzVx1buKgc1yQWZQSpFLEW64RmiSruF',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RH7Je258aKCHcsGk2NEC3AJx1KhMYjjeiH': {
    'private_key': 'Up1j9ut1YZvU5JpivQ2E4qoF8SBaw6DoDfwUt4rzF3JhrT8VkHZW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGpnHrYpUdimjuWSZ56Eb6hfhJjgZTgV2k': {
    'private_key': 'Utep4MxK1Ra3SWuYzrSvgR1PiWsYERpesRf1mma88PjvPqFtjHoK',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTUmqZNEwBGritUyyZxhUBv2MkMLatPKqc': {
    'private_key': 'UrTJov8TvUkDhG6oV21nw1f4PZgmUcyV3Bmo4semL48K6H4aoWt8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGdgA2fyGkiN9ZKyPsGWUeZd8EgvNV8unG': {
    'private_key': 'Usc2QKxyazM6TcmDTNoXbmNMW8z8c4gUwEXY8Q6E4kASKgDhaYiF',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RW4Dm6td7cJLWKLdM6b5EwQZyYRgh3KNZC': {
    'private_key': 'UtMAqcgfPDFVLeKw8ekvvvzNURLCqNYjSSvuuvRHxFvE1yAU5ZCB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRnbxgxXN5p1S9Yw1W8PjcU6JVmP9GzRNb': {
    'private_key': 'UvgrF5uUDLjR4gPUmhKNhMuxdPJM4BEgVzDT1Q8afhzpfj1x6Sxo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKNz7Y6xndxdfPTxvXM91vCMpUmiBQwN6C': {
    'private_key': 'UxWFQRbDCjMxrYJg8xu4RNME8Qmvyniburw9AmCqCdNyFMogpyeJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REqsqGJmhdecYqbQT2smaL41dcqXxAzW6F': {
    'private_key': 'UpiBVs8w33vqvDMdeSeMEygAFnhdJi9RBDeoAETpMjiVv7HZ6dWL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQceBQhMtjPzmquNPehQg65DqMvkrxwwpB': {
    'private_key': 'UtBZJhVPRwGQt35Uk13oGip5jZF7z7DVQP32LWtBuCMpasRU2RCQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUWt8Rc1RawFgpyETKB889q6cjuddpB1kj': {
    'private_key': 'UqqT2MyPp5bnSooXCdf2siFF47AWSEca3JpDSBX6edVNyRPqX7mN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RE23WToZNyfscqPpVQFM51gnkDLriEvguA': {
    'private_key': 'Uvomxsk5K2y7XUeJyBkjN3q3kmT6G5DiF5LAqcr6FasSDqyJ3sxG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBhgZ8wpU13jHVRyNjCNJzzrJDmag8Qebq': {
    'private_key': 'UrDzFiaQmEjbsNQk3xtnDEHcMbw1WJaa9Hi8JpgxMtMjV3D9yLUp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQbsnfmWTWb4jEyYoS3995Wp7yU8UXRKwq': {
    'private_key': 'UwfHfSxCTTzTYrLwiw54cf8n4rfPPWSQDHEgsNr1tCrCXrxAmGTf',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWBZnDt1Zixp1Hm65ZepT2itf9pKo4mBhX': {
    'private_key': 'Utb2he1dpHizbov1uTqMyzTkgDjotw277DM548N1aSmThh51iDFh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RB33kB9u2yiP5tWGMo5NXPmfqCo374FLfT': {
    'private_key': 'Ux5MEC6HZUPUFGsATfSGBDjnGvaBVMqwbdnPwLb9FjzURMxwrK8r',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDCXCxcQcWwvqhfL6ncxRwfqibKtSto765': {
    'private_key': 'Utfo965eyfp4srPDjdRLrR1AcSPmo7X996egXuEg1FpdAQQ5LUJt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTovQCS2rVjJrkoxipDHXb43uTnaAAMM1g': {
    'private_key': 'UsXJhaWE1GhhxiYAu83UqSvN1rmmEb58QyuavzSGB4ai6v8eWvbo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLDHxwz8jcxrS5Mj9L3YL2X2SJ6ESo1qw3': {
    'private_key': 'UuLuRxy3e27tqk22wZq9ewYeiryFJ9hUF1BNYPsg7WXpVSFwq5Dr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REdj5phyBFN4XBgzJ2bcXN8cjCgTuyhyuH': {
    'private_key': 'UuMRkdULqJ5HEm8DQehzLexLoDALW1wjLEHPDtquTts5WpQxGagx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJGghX4yD2ic2Aa5VvTATkdZycMiwxUYK6': {
    'private_key': 'UucYJ3CJk2fr4tpQgJwStpL9at4n6azZhFC62K9hDAHUjjgV1RCN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGJL3d5cDFNBKcUnyzcjhNwVw6AfKSYeu9': {
    'private_key': 'UqryFMCRkJEB8YseUEU3vH7Q1UPkwWx46n4WGzRxFULDoAPokPb9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSwVZjSyRsVJGrMEMzNEokP9pUzPRJi7x9': {
    'private_key': 'UpgME4uAaHEBF94DwGFSLnFPAofLahRofaGcR9L2f3BkqQD1d8Ti',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQEPh87sGz6DgoYqxpVucFkzy5xUXaFPjn': {
    'private_key': 'UvinQCwn44hcD4RC32MjqiAezspV12HitWyCVYTeY1owxBJD3iwo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDqzJtPY7K3USmvuk1dasMJ7JiL3d2pwtu': {
    'private_key': 'UrszaLomizBHRDcHfy2bUNznsaTusa2YG9aSs8p4k7nUYmFaZRag',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVBdE6fdHeP11Kgwzuq7uTqRuhwpAuNhh3': {
    'private_key': 'UwTEeYdENt7XgtvneQmybDyp2kgE2anRAGkX72q4XxMzVFgStLs7',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDv5NqWVreeLbf9qV9wnT8hYdYoN5N6jdv': {
    'private_key': 'UpeqaRu4R2LDJnmhmEFKZqjKzxbdWP5adTSVrKcZNCSoSqvQoAwE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWL9DU415ehHEBoo9oz4BBLt8gFQZsRmUe': {
    'private_key': 'UrjCwgFbFCcGda8dbgmAszDVgGA7zBsAiuKyStnfTQYh3qRgfi2Y',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNZZzCBUtFWz33EWmcQX2yyuyMYXCgzRLe': {
    'private_key': 'UqUeLqJE4jZ7vaJGVq3xnq328BFzbU8EAncPrBA5FhtvfSoToPoB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAEhcyFK7jVX9uFGkrqAzbqmWSw1aWEmkM': {
    'private_key': 'UtWfbBGJMJZKMz6WKB7NSCQEY9SKXZn6Ukxhit16DfbRCYupVzZh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPqD4qg7zzX6kXqnTVEMZt4KdkgXx9AWky': {
    'private_key': 'UvsEnuwDBvCKkTEr8AnAnksuZJQcFoFxke6DLbNC1MuLGr86MvFC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJbYEutEVNHsNiB5rqkiTh4vNMkHt6NQUz': {
    'private_key': 'UsfvXag6tbBUsVRizGmQz7rWr2RL69cyBsDZSKK3tPWfxke5F8DL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RM6kv8Amr89zWxSftKvXTieJA92JySHXRr': {
    'private_key': 'UtzEWEahYE3jMp4GnxXDxBxff76cLx8gX3JTCg2LHuoMGBgH8ZDV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUbp52E1GJrm2UpZcwHwPQmvHYBhZ3Nrdp': {
    'private_key': 'UsPXcEDuLwfjLEaKKrn9uBkEpYorez9DpjVLfdiNos4pHC6Guuvq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMogpS7KGJvrZwZnyrBmf44ttfq7QV6Y7P': {
    'private_key': 'UxEhB7yzpPfMk2mJ4d8rqfuhyKGXPr5RY3KC7FMJBhi4rJgDMLjq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKEC1RFMaNFjeDaiHHPsEDm4ZGQKssPwj2': {
    'private_key': 'UqZd6WK6mtKghCQuNhhd5Zg9mNYX5xq3kDqxHJeDksLQonaeNoeq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJWor1uEWQzWFoU3JbR23jheDBjmNyKFX4': {
    'private_key': 'Uqhpyo63Bgc9s7xA17uMLjkcCxeijEJR1343xsZHhRwYkbMYMnam',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQNWV6KDX9j94uQic1jyVTravp8wL1esGq': {
    'private_key': 'UrSyScyZNpy5oJxmbYVYdPskUZvZJghjLgT6PuSrgmRqgHkEHpRv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RU8J2bwuz5pBCJ7ouUVqaLqpoWQFizVZN3': {
    'private_key': 'Ux2b52cj1oai496Rmn2YnSMiYDcKNxrzoM9A9KPwYC81dRussczX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSpyUD3BVoshqxdoomN2RMAwmu7Qmuy9UR': {
    'private_key': 'UuYM669jfD4ce7rAzCGM2ZvCKQR4vwpoWz9aswis43K6UGrc9kh3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRStbVz89yhMvjwqP4BA9Uka26Bi1apMDU': {
    'private_key': 'UqanM7jVwxPQfJfn9u5t9nZAVPhZT3eRSw5LNap1anrJ6znfRvdB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMmZANaM1iAk756wRpdzh466Zx4YWkq3e1': {
    'private_key': 'UxZ5arLkdFKf5ex4MhnhK6TzvrqmKzpArdA46gBvarzrkmZeQiAn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTKNhSkSRsgJx4a3y5bLPC5gfJAWPaTAao': {
    'private_key': 'UtPkFsaJH6ViM4G81GCPnyBxm3J69ULrc9ULvkWhbB2Bm6ZHGQ8Z',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRto58cmfyVCTzSjmXkJJDcF9ehYCT5Svu': {
    'private_key': 'UrNawYh6fVvisnX6FsJUFuFS7sx6CySEyBiH6Yh8uaGfjQQiehAG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RESDBKW16Taj5xQp5Qd7zhXgTYPvcvNRrs': {
    'private_key': 'UsBJrcw3m7xG3DSJxDYqkZKUC5Gj2hsZeFbL8yfyPAjodbkFt7Pr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXbHC7NbNfzLmXpjnm5i2jVAv7ghWFRzD4': {
    'private_key': 'UwGkzm36JfM5c39j2LTmp1AXsVtn5kr7QyNHzfZs1ou2vX79swnV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDesUhSZ447167NDtxvJKprvNN1bCPVSyt': {
    'private_key': 'UpAqfSeAjRpU1vpsGTbxBNCZgbkoUSWkpCULsuiEpzqxNtKfVYo3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFwC2tH3PJbTAJTGnhTR5Xy27dZaVPSCsA': {
    'private_key': 'UtygeP5ZNopXg4kznHu2khgak4bpBtHD7QMQw2K42pNr7CWr7d3k',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMGfMSLu9J85LGVgh6vJZLHQ4Y6nBsLT7z': {
    'private_key': 'Uu17FHaGLxP7co1EPDwbG3AxbsVvY981EcvcKW4FitGQfg7RgZyp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REYeXgNezudB5LhVQHdV22DxZwVR5EEAcr': {
    'private_key': 'UvmJ3V4mhESGFoqHUGrZVgjQWNF5PZziFd1UvAyyrKzgHRX3TCgs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RW8P5ADQMvznmWoogsYaUVfNb5oRjUmiN9': {
    'private_key': 'UtxkkBMmdA2hXinn1CBFyNXQp9ik5iw2wJp9jmZrQfyPQgFe5qnZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRZepuDTkxYPz4VitMbN2Y1P93b8r85Bik': {
    'private_key': 'UueKRnbUPZgyddA1E6VgsidY1qVasCydAYoMohwF644XbCnQddxg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBgnvh921aP5E7sfB4N557PgSXH9Hnk4qs': {
    'private_key': 'UpGk147tpuGrM9yFhWNHf64iCTwLHCeuSFxq5kh2nG5r2uAbxycZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSKje57hUVwRFSsXUscv74KzEz2sQau4zT': {
    'private_key': 'UvNLdFLR5x5C8mV7RX39sujE6EY4mywtAZ4iQvPFzYZB3k68CVDz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLQKC4AV4eiygZ6skiU7nA7VdL3TvGye4X': {
    'private_key': 'UpiKrrLmS2nLLBp2AH9oU5xETeewm7BoyB96Gw2NziCZHgzxUFM2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVwCzpDSYf5T5Wg6gKkbdcUeMW2g1dTYmt': {
    'private_key': 'UtC6UJvcEGLyPnKY9MdZDVNADacKvkg39eJLUtQDKHyA7DA5Y7Se',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDkH5F8ASXccr2qVGGovYUqp1LWLK9sY3z': {
    'private_key': 'UtHCPU1qyXeU9RfJM8oKXjxENN9zSRGpt5WYbUm6YAv2NtzLT2mm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSgt4LLgbjiD2kyztzfhhxNSsVpCvJCfBf': {
    'private_key': 'UpRWhpJa4VjqsgJ2dUGUPFry87jfW2FhtDe1mZCScAHo76tde2sV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLkNmWpzk7Dz8PUxLK2PF7hSFat6s7NnDP': {
    'private_key': 'UrfPRsDHxYev9a6Zx7M86kpK8maC4csnwRYWmXpX1bcf5UtedRDj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMQ6q2xWt4HLsbBca1PqGd3oqYcb5y8W4c': {
    'private_key': 'UwyHCz6bPa5skkBB7CDFfGG8k6dieoo7LEt8Ajxc2ZmyKN12s7SV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAFQALVvDvrKza939GVhDFwqwN3HKDYqQD': {
    'private_key': 'UuoaG5RUSB2hcMhXoh1AZBDA1NZz15yZMaKVEwhCwo17ybVveLbz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNgbbv8sBpQtCZBfyfJfvrhJEYLbaz5nJe': {
    'private_key': 'Uq5VVnQpvVdzF3NhivBS2bQtdsd6DRcewMz8jZ7nC1P6JEC1CQsZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RE81Q4SozqQHqq93LoDFmWmW7dvJTazGLg': {
    'private_key': 'UtuspyCJ3PyRaGQNcELUQkZBPwLby1ZSvry7zJmjsMjH26fzLf7x',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RStfawdKivntdyhvzP3TZfai5PuNJ1jfgg': {
    'private_key': 'Ux3mmRTPUMW4zVdvZjbLXREsDfQzWzVgQ1rxNAuqzcxHExWQo99Y',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJefapWQViuZMbYZ7QWGJm7ydkmYjvQe7E': {
    'private_key': 'UxPqZzC7p4Z6LffS6U9hfKP1VdRxHHQfndReod39AFaFGXa65Wqt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWrWk9eXA8uMLFeS6THQdK6WjUCMVMA5z3': {
    'private_key': 'UqvRf4DKiaiAg92B6mgiMNVEGGd69qEFRaw78jR2T8CeRkuCKHSy',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCWvFgaYGgMk3FL97Q2WuXEj5wEK8k9HGT': {
    'private_key': 'Ut69Coxgwsxf5Yp3S1iQhgVRiDXnXhvyQnpBfenJ5GN8dVQpHAev',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RK6kXcaT3RUzV3fj1os8iEPNh3Z9CBSme9': {
    'private_key': 'UpLqJV88RF333F9KaQWayWMCABe4LxsCt6urnvKW3gAiUmfVjKCz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBCvdLS1FyeG4YyybDz2kBLfBNLy7Jze6u': {
    'private_key': 'UsPwt1QjwBSfgnAXCVVzfUHKfLD9Qy9DeMUYH7ybi7zvKzr3dMxo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RR7peMBmRccWBjaDxbm7nwURda65WssjEx': {
    'private_key': 'UvZ5v61dYZjKsQXujxjMooTepwCWrEP3Frd7vAjZ5ogqzD4K9yGA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBH5jhVVWTc4zoSLmrQwQFe9uh5vC643LL': {
    'private_key': 'UxQqUxXyvWLN519bjU55rP8WpmkhDSgo7Zg5T6ekezu6HCLnR1g3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSeFEfgWr411BqahcRkVUebVxyhVTQLCmw': {
    'private_key': 'UryEJtjoJh6G2nssvfxJxErP9sC1a9TsPxFQLfpoUdYXNLqEwgtu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYEVyo6UyWe1oSvsTNHvvHZy6Uk811Zkob': {
    'private_key': 'UphPvPV4hecY1rYQz8gQJJaYr5S2AGQLfnNE4x7oGdvSt3aB7CJi',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJfeMChkQfuRef8c63Z5znuY67ZT27siyc': {
    'private_key': 'Uq2fuhSjNxyhvACuvAHBx3Fih2n64FfV4Eo4gAFSL9fJZcJLTnv3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNnVrWpGtXJUVPf6snon35pVcTnCFLtXGU': {
    'private_key': 'UpCqMvKbdyLYRTtZeuB4UkqbGosh4edw7NSVEadZo9XNHd8PzjgV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRj3brBaqi9nf8Xd7L2jSs2cBoSXkWpEMX': {
    'private_key': 'UpPytJAhGrCJaS75bB1BGPgBSVLNvcjcr18iybQR4RgN25J65DfC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RA9YWxib1XpGCXd85dVPfgN7ZgdgtzoqQx': {
    'private_key': 'Ur8xknr4kWC6a6wwPD8NJ9GsjEVqwEmGwtbwcQnLFQPV7nnSGfgo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REMkETvEEAx84qyagsD4ZYsjCnVvHua5K2': {
    'private_key': 'UpYj8nWvr99TtV8Mfkm4fTMxrirVALSZfbGkyf6b25nUFaA6yreJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNfng2niEDCxr7nz4hGnV7MG73NqindJLS': {
    'private_key': 'UurfyxCa81nx4dxJjUD1PvZwJfazfRYmuRmjtGvg92HrpjcJZb8Y',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX7g17RnzMejwcoUGZiNP6GQEQXp52QQXw': {
    'private_key': 'UpiftVDXkoN2y96VKjrhv5cJ98XENP2tvchKVkVMKMTDCykrf9MA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9UJy5F3Fq4pW3R2YDqXpbNn2WPgoQT3d5': {
    'private_key': 'UwzFM1HxAXDRnEvh1Uj9CqmHkrKvXDMmoPniVfHMWzBukBQe4TZg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVBrKu4em8wwn2GrNDkkBTnSqVxiZzdgvi': {
    'private_key': 'UxCd1mJEtQ3XjA4ij72Rxnv7USb61TPsUNSPR4v119uV6iHts5Jr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRHgDZYvJBJXRGyAYP1wD9sEd4z7Jzd1Lg': {
    'private_key': 'UpCJvYTwCpYUogaQsv2VXzsnXe4JsXYE1CzhDQTgrLG2DhGb6mQv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RB4asFq4NRQyzdLkPSL1ExSDXxCAysLEgr': {
    'private_key': 'Uv38HHUbfpqwD2YgkdjG8eJHE5DisPgUCs7WF6iRtYZ2YbHdQbcQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRUh8ARCkKKm8hqV3PwbLkuX92vesSubGH': {
    'private_key': 'UuGDiNgVx6c7KhvRJkFn7Mq2JaMHEkzD1HLB31RwVzmG9adpZqaE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWVjPCycNDBW6EKzkzrzYtvARj1QCA7mZZ': {
    'private_key': 'Us3mSVBDV6UJ1w5LUfjSgUPXv2tNKPvv4PYkXcoYr8nzjukQnq79',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWi36xqXyNbptdAFmKFTDbeoAanWduZui6': {
    'private_key': 'UuQnGBcAHN1ZYzZEHh51GWH38S9UmHxRMP3yhvD5dRPDcR9dXTXL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHzmvS2XkkchdtJZb7Y4oTYdFtNtFo9UYJ': {
    'private_key': 'Usza3KvPHz1uf2iLoekMuHeXQtqbm7V8HK2mS9wx6CXqWG1dUmky',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQ9h8PvFZtdqszu8FpFdf3KRoSY2fiL9KF': {
    'private_key': 'Uq7vaB1u2rdnK3Js2eQKFBCzQxtDMktYZLM5Uw8kCucqSZwUy1Q4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCytHaNWAsHortKCy7oWb2aCEQNNsFbzTd': {
    'private_key': 'UrKDgyaQXvpoodbtq3WoFtxdWJjPifp5UhYm55T2ASztBTdxMrtU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQ5qacDCM2YPJoHYpb41vLrot4EJuax9Tn': {
    'private_key': 'Uq2irfrY6jzDfW7epN3PRJBBRXx6xFG1NtL3UJFNkv2SGBvgJxMs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNzi5NaEYQtiSSydNMEeHochRVjjyzN7vC': {
    'private_key': 'UxLT14RinqwZxzyHEmFi636WU8JbZnt1BHEDfaC42NDS3ncTN4VV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX9hZQ1X4YeFtgonSx4JD4sVzCtZdnb8Kj': {
    'private_key': 'UtA5pbDB3EXWr4sRRytY9TsDnZhwoqMDj85mKZg7afSAgwrZKRwB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJY9aVbU4PEz6N4YHGKZKfdsHon1zdXw6f': {
    'private_key': 'Uv9pYKyCfQUnt4euoDummAvhPdti2vC8PEXes8LJkqwouwZb9yvx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHpsza99tGdNk2qU52nCKhVJMaqtQ7Zz5p': {
    'private_key': 'Uq5uvNUSvRrs5qD4hWh4D4tMYD7CUw3ZH484DdDLkJ4thvb5Pcjx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGneXScKReVV4uaKu1YphpFuXPWdDcuqyh': {
    'private_key': 'UwrE39BAHntC2N3JhM9bNVGnMY6Nn5NsJBobkrqHGoCgPWGc7hLL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTaGYeoru496bERJWrTV2kwj4ugCrN14nJ': {
    'private_key': 'Uu6Jf9m4WLWQatxz7UXiM6aLryifms4RBSnvrQFBRkzKmVP4sZZn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMriY5RRoiVTgEJUrxvg7auvy4Xof3EtkG': {
    'private_key': 'UpTEqgrDDWTDVn41Z4rmY77JBCpnZnqrubNdypiywQrUUwUzJw9z',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9UVgnavsWURsH7cjQt8jNjFS5rgTC9MWx': {
    'private_key': 'Uth5dchjPARPSyxdZvwHTR2vYaZmLfwAB3Up7okSE3UrFqBxCa6G',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVt5hLLRxmMRkzHMcSASocXTTT7jVmoh67': {
    'private_key': 'UtmMQyKA94u5UYv53chYxAxK9JY8eiCdXxBLLEF7AkJA9zCszZ3f',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPiBMX6AuR7yM6EYWpuJRK8T5zhniXgVYV': {
    'private_key': 'Ux4pGDepFyWBp1hczuKLPsbwvwKGW1NLZAzcA5PeYeTxzD53PU2k',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHZ5wt7wTnikx5Ye53cT7inSygP4NZNESH': {
    'private_key': 'UtGiuzTzQXnUBP1XQP2wzvCEQ4UThbSpcHaEFGgjvA488Q5jWLDU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKZKZDRd9eZMRtvNhJgwfi1NdG9WawKB9i': {
    'private_key': 'UpJwTfKdCqrwiLDkvDf736TiF9RiMh2DXCwtkRTwY5NuCX87yZAM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGCMhRZsJa5FEPEPARdzxScv8s9ooYr5dL': {
    'private_key': 'UpLdUoEuhfhZP5bWYyvMiEAnoHi8y3qWMaeRopXj7RUD54Dx1BZN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RF4H6YY6xPuxUCsFY9bvSk4p4ymWdfznii': {
    'private_key': 'Ur2JrFgo6X55TpybGAqzfCqaUyLGRJS7ZGxL1kUJU8e5P5KZqNzW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXYECT17ZbQARQsvvieWChP2VffQHhVRm3': {
    'private_key': 'UqJEwtNcgnt2W3S53sjXPxdt7WyPQNn1QZ8nYQf2nurV9eHSo58Q',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RA8kVDBwkJysyGGnxhiiudzXHkpocAZo4T': {
    'private_key': 'UugzK7zr2TvP6V6fDjsr4pJw6GzGb8vpwafWze4P9AjzXxDn86F4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKM95KX8cCJAjuG3e6ZznNhH3vgyLmH7Ef': {
    'private_key': 'Uu3P1N9GbuQe2DGEca79DszfenZ2DCYf7WLB3Zw1bwCRcJpicJ9Y',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKvFL7XXCvzpXg8j6Zg8jb2brjkvS8D4M8': {
    'private_key': 'UqoBNh9fx33zSfx7wfKoDutmJgaQDupN2Vo78a2279SHzBNnjwLp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWNT168FyJPrxFQjinCrMKvGPsQ4RM7iqJ': {
    'private_key': 'UtcUNPUXpaTMuyMvAL2T9AL6Y3Esq34dvevxYYE2xhnkrURsFKeT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSqyT4m1bXUGgHfLTthUFFQN2d2zYPSeMj': {
    'private_key': 'UuPKojRiCzMozuhYTBaShpFniy3G1RjDoC2o9W57L7pQFz87o5gc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RB9AWMCozkkegkSCrvL4f479BkYacLAd5W': {
    'private_key': 'UqrtfCkbznbpBTdhDWQFJMihATf5Bupg7j5aMqXihPEJwzUEs6H9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMDRKwKLHQLgNwR2jrLsUUNvY1JrqUSvsu': {
    'private_key': 'Uqae4sbGXuFmDoxJo3U2qtmhT8NWo4hWZiVGkR7vxejmFeLre3hT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNCJRfpJQT3JLDJPHcN4rXzcyesGPdB3zx': {
    'private_key': 'UrJfDingw7xm1tmTCdbd74s5mMjGvECptAg9yEhyfMFRQX7rkwzM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL1PtoN21nepPPWfAkCzWRbJdCPA6JE22X': {
    'private_key': 'Uue8MgTFysQjvNAsbezVcfp4FDA981VL3jMeztexS9gRK3QEsKC6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAYhMfe9DqK9Mm3AjxK4p6WEiGww7PDcN1': {
    'private_key': 'UvcL2Pp3Zuei6Rz7pQvhQ92gBSHvrcNkrSYtuHVxuuvu6qGDy4L9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGxTXo9LJQspYVJsVgUc4vNe4cdYLyahiF': {
    'private_key': 'UqmQB6y7HjeyYC5vL7ppmiZPrTfWRCBnum9JKkiuvW7xpKWbcpy9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUBJiz2tYMT1t8dXmdW2Yp2uJ833u4mbjU': {
    'private_key': 'UqKjf3NLg6yUV4E4ieKkiFrgeksWULXxSL5KdJWEVzbzo25XZRXz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSdMBGf6tWLu2KCvFtnYvvwdoo39iZ9b8h': {
    'private_key': 'Uv6SyuobC5tNhFHfftasKQAgQjmqr5jww1jSyfVwNSqcCHYMyhe5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQPRV5Zd8a7t9Vx9y64L4JT3h3BYodR8VL': {
    'private_key': 'UtdjDV4Le9Njx7EEjp8y5ud9rWqqo36sDzFqowKZPPuTP5P1eFFU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDUnuAYtmNtoxDRrjwQsNx4RMiidszmwyv': {
    'private_key': 'UtKbiUCgABHCLdQXtgjyE9jSKHJz9m3WAUsHiB8g9xPcNgbfDEjP',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL4i5QZAFhPA3D3i59XaCxju5x2BN3dTmZ': {
    'private_key': 'Ux91vvrHtsmE6a4xrBsd58r27FTp3sLt6zyCxBph9jFoUFvdt8ji',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLXJPkJa1yUGWyWHXyTc1qo2n1P6oHNGHU': {
    'private_key': 'Uv7qvVVRFNPaffrLM2cDm6samz4C9H4iLbcBZHq95AhaKhTKSNuM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKrCf8zTFdarHMHs5GvnWM96iSWGG8wySj': {
    'private_key': 'UsE6a9L5D8F1JdfFoHgWHq2HWT9DXsKc4Zge13gs7UU6b6TzPvre',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVbLEtWtpVuUSooobcL6P8UMe9mrVw1CCB': {
    'private_key': 'UrEGqtRMNTH7RYKnLk5vkAKfeqVc4rbT7sDk7kHK7rNyvLJHq1EP',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFG9zArG3D82cRn7DJ43dN85bjCHft6cuR': {
    'private_key': 'UpxGdB3fu8FhsXj7PDhkWCSdzMcJJVugcZna2jAaSW4qRRkrEdnR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX2LBmi7UiPwFYnaMFK8tSSrAQQiKp5zKH': {
    'private_key': 'Urgy3RSurcP2Qk4uogahvRXGFoJ2G9eYUdNCcjHU8NHrdFUHpYwi',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REQRRPaB5GUncjY68DwmczuD4Sdn2dYP5h': {
    'private_key': 'UutSEZjP3jR7rppiiuYMPSFDAsPkU5ARJiCxoRcg4ob6UzJ8skVr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJVWRyiGokrj98ZLauBXL7NJT1a3krPBqf': {
    'private_key': 'UpoBCeLkcT2aVpY8tFsDkpZzDKdTABbHpMbUkFKBCdC4FXuimbs9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RY76Lsx4iasYykg81qdAzUvN9HDWpWez6S': {
    'private_key': 'UwRJa3T8PTYG5YevNHJPu2XSBR63HeQfsDmB5ZBM5HUgKf6ZSGtv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMYxq5MTAGtpus8mkize59fz66jwEkxRd3': {
    'private_key': 'UsyMBvsGNDYnuzmBAomawLzRMztsuTCLXtsYQyfBS9vFceZQi5zQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRkhjJm7KwxG6bCuLxbmjLZeKQS4RQeuPC': {
    'private_key': 'UpRbReMTXVXbSGmH9LQ6x3uLPc41Y3WXvNThGfSkWzcksgmjfmFc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBoqJU1cokiEZuyxSXrJvZQhpvfArN2qeb': {
    'private_key': 'Uv5nRzyhTKtt9qW4uvpUjhfygSCJQoe7K64VSNNTe5AHFi9Zn1zC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RB1NAjwDvr423VHKkBusWhHyStQhVvf8t1': {
    'private_key': 'Up3HJJd7GYaugsC2YxqfcpjWtxCFFDqQW1M3T4dXsnYNQeY6xRUe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RT2zwHDJodkA2ceyuT7dDDMutv2WAitK8c': {
    'private_key': 'UqR5BrHYCwdM2QgupStqL5R2psTE6mXeUoywYWLLWke4Aawoc4mq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPpecS2cEKTcvsfcE5iB9Jdc2LUbM8jBfu': {
    'private_key': 'UqVTb6B2pxDcHpQXLXQRYoHKkZZcGpS9QE3wASWyjsKv2eVsiqZa',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFkMcjDqPKqrWV89wvxCqAqkEDKEfdiaeX': {
    'private_key': 'UrNmRDNzZdMMmSHbUC9shRLUx5N3evWtMJTha6TnP5bQE8FWxymj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGKqF859zdkmr4P13NGi3cdtyZfNG2b9u2': {
    'private_key': 'UuVoCPijWB59TyFCdpwRuw8hR4bzws2w6DTkqETCiUhyuGenmADJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9vqucgPBmyx8j8rqnFM9bjgkjseqmXCuj': {
    'private_key': 'UuP3GyGsrit4hK9eGWfFGDvXpbQB6PnLv2EhhxJ4aTcnKnvxDDpM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSpWv68ScJRfci7nq1LoKKkLshyvKheJ74': {
    'private_key': 'UubayWjVXmXS5CAW6RHQxLBT6wr12ajzmE2sn2dXgTZ4yKRdunZW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHeVXrH6BEq1sYmKmLJRSqMdJi3ADWwtm5': {
    'private_key': 'Uqu5eCfmtjmpDayhfAhh27MdkNdensnFvkT8JZeKgrzQXGn6ZA7h',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNh66bTfriMZcD4rd5FYSUBWPi1fyqn3ej': {
    'private_key': 'UsfiJU1qEGaK4tJiYspkX9EiZJRHu1b1H3BPYjVC2jbYC17xiMwM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUfJe8xFgsmnyFvfkco6MH3MJbzD1v5Jsh': {
    'private_key': 'UtJizZP2TKDAKFUEwjwVL5NS84BemveRxfEsSz4aywYVXXQ9MMVA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTm2sVfojWVv727b9wAPfigji4dpi6fFL3': {
    'private_key': 'UsNQhpGnFPxLMKW63qcH356nSHyrix6iQ4DURsd1QVGFkUqGR4qk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSoVwik7RgJud6fdd8LNSBSWTWCtdN1vbU': {
    'private_key': 'Upwidg1He39eghoCwKug2dtR9VyQ4pjhmzkib63yc7NEaHwXEMZZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RD8wWdsx5LR8TYSN4EaxTBakFnfx1toSzB': {
    'private_key': 'UwYi8hMbgU2NC8Xyd1NjqxrXBVQuQdNhrUoc7atWea2eCNfTskBA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTRDV6vNfCZvnBMDG37PFeMi7KfQLcopup': {
    'private_key': 'UxNn4Ka2UAEYu5AFq45JscQZL21NaDSqt3cHt16pavGnVNhRA6p1',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXERysRdeQDMnZ6TvoLjowm46Kij3XC13X': {
    'private_key': 'Ux3ecJwW37Jb8kSpNBCJZYnCt9FSGKkq26UBq7LVhDRrxFRMdWyC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGgQMeo3GRj6iU5aRJjQfDAZcqMkrF3ukh': {
    'private_key': 'UxBi1CY1PpZErXYRD6SSPnwb32hzBANGfJUnRfxDLAKUfzzZD1CH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXu5ZP7Yq6NZnuNaJba8T8PHLpeLrLCcfQ': {
    'private_key': 'Us7M47gpKXTrjfRvtZpgvbc8c2pqKMeAk17tahu81QaqWFaLkad6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RG5qMpDbSbJXrehvYHevGmMJoReirRUcot': {
    'private_key': 'Urb77HQFYi7EqPpF2eHMa13yjCjSGPVNVUuLBYEtF6ubwFNVW9C9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RD6L7NbUeuwHMSCMDmYns2PtwBJN3kTVVQ': {
    'private_key': 'UrALQQWiBJTFnA7ZSuDBQ9AXPAJvonu7xMbQQtpf8ypgf7HSYwpu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REm7f5qHzT6BjYWsoy45mD1r184dgq6mAU': {
    'private_key': 'UpFynYKLZpRHytFGi9PiKcxPK4NmikkAMk8rGgkZhbn4uGxHXNSV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RS3ZRUaP9FE2ji5tsns99ohScpAJzgjfir': {
    'private_key': 'Ux4sxLnQ9fpnpt8wxsgBVPZXASDR6DhFNVg871uEK7Ca3rE19vGT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRsSiftmhgyzjPdAerXgfyXDFgPZ7FWj5g': {
    'private_key': 'Us6k7mWB6WoziiPhi2MkDQgadPyYmFeFJ4aMeeEtcHcPfpmVhNmx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHWMXAYCER3qEVkBRsWZ7emUedDR8FpTxH': {
    'private_key': 'UwU8kRzgAjXuXWripKSrnqE4F96fgZ2rbWx3oxUgeU8wVFGHq9tT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAR5aE1f5b6vqjeRbtHen5ZJVEzGYuY4gv': {
    'private_key': 'UqSDXLHG13oEJP9eThzWZoDPEGxp7yebfx1i1AY4jBYB4V7EM7Jh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWZzEfa6TJMZ8UADcSE9dLaagL7ApDRzAh': {
    'private_key': 'UtCDvvCVPtBrE8XZyyCfPBZ5GvJx6zFxsXccNjyfCrN6BVVmn8fs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUiepgkhpsBRWfgPhb2auHzYp9HagC1xBv': {
    'private_key': 'Up9NvHW7BkMBvknpXsEaYdy72bWzSxZycWAGQTKsZ2AKspmGiqcJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAjrnXa82QY4j55v5uBxXuTYRchgMD5S4w': {
    'private_key': 'UtaHwNTvJs8Z8NqR4wH7amWaCH1EZTDNeS4crFQUywx9u2u2S7Mb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYKAZxfmEyLHKiVN2QrWR4sayg3A6hBzXo': {
    'private_key': 'UucScDbbkna8hMVhmQkaSKhVhYm9pD2RzWteabJNhiJhuxHBxZ9v',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPC2MUAZnCgHQiY6UZDvGkuZxDnBbPmU6u': {
    'private_key': 'UrRDUjaw5etLkFVjgBFc5JxWmJjqsJsxWGbw58ND1ZBkvk92KDwU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVfSXoDSasjhkU5ezQykJX5q7EisZcPrpY': {
    'private_key': 'Uqj1tLxfjMN2Prjda3z7Dv2KwzsMg3JhEt2z6Udzdn4MPqDzCFrG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKoHCNVYSjxZV8kZd9mX39d2V7W11Z286L': {
    'private_key': 'UpwuXJxDMjxTekmHP5yzbWgfH237BbHxaJEzV65FatohJ8AYpEN2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPek55V9bbYmYqYy1ywaFqrScPjKf4sMJm': {
    'private_key': 'Uq4VJQcQ6gXCf5MJrVygWNvXs2dxAY6ZpVqyvbUGyySh1HB1EDZx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX7avRpkF6DPctSQf7t4AJxQAHjwjrqoku': {
    'private_key': 'Us1XLvaMz9QpCnYwZ3j7AJub2GzNXbfSnMsfrxUz9PkBBZyezQxV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RV2aa7e24mPrwxpTbz4Rp2XLbH6byk2fEE': {
    'private_key': 'Upu5UEwC9jcvY7U58UagErhMzEa5nPLT155JgP9Atmy3L3SLGH9K',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQmqhzybUgHYKdBL5KdmKBNkxLVGQyzRdX': {
    'private_key': 'UuoxVxKeSG8hDAnnzdutaDM2F7LRYmBfrfrPPafAmxM648jhCLNf',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLjn4nadTEK9r5FFqkd7GVB3wRMniLfHPv': {
    'private_key': 'Urkcn7BxDgdWXKTV1gBDe1PxMWo6zuAYbAV79tj1rgaKVGDPxNL9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9coXHteu1PxpGWGT5PbciBs5QH45reN9f': {
    'private_key': 'Uu2efFpHxaG6R2egGdKMiRsegSTWGnX7WuuXFBywZRf3hLjs5E1f',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHVUvA1w9a6eyM7uNaXyqEHY4zymhdRgEA': {
    'private_key': 'Us8Y6rfQMpDn4PiGRptpDkZTSWsWYcuoaFFQPviifRviK4UCipw6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKjdYJzGRQapMSHHJPWHbVeEWvpfRaGi4s': {
    'private_key': 'UryzDg3jXWJwJHfZy5SCU3dBAr4AbiR8sECsN9RuMmTYT5eBJu2c',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCno152Zh7KyS98p9WmpriBqw8FLK4Tb2Y': {
    'private_key': 'Ut87r4iwLuU4SKWn8MwAbnaDuyTxh2tonzF6LcyhwnnxFXryhxQz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMaQBdKr7ZVN4tdduV3WKPuYPmwUVxJtuv': {
    'private_key': 'UrQ2kmZuHzC68kfminVVdRoXtPePb3ss7oYcFnwKKqfmrixCFjzg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAVtJPbJBvsZeVENGJa7ATY2ubXsNCkAbC': {
    'private_key': 'Uwsmm1CtSVmt6Mq9zP8ETTTBpFYY4VjKztukyvLkd1kuSUpdr4HN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRsNHTNVGSh81QNnFyikasdZYJDaeSVB2f': {
    'private_key': 'UuMyWUF8BGVA9n5cqgZMRUd4nj5yoFe8ShEpA3H8MicVNfFe7Y6W',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJQmavoDyXoYJWx1DxJWUxnXBcicjqr4zo': {
    'private_key': 'UuseTG5S3VecFMeKtoskhQN7W1agBwrDYzZWRzXLVLP8g6LUKHxE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSa8Dza1DWVEPW6rMLCa8V235fmLMT5iFm': {
    'private_key': 'UxF9XBcJARKLvG3NM4dotUfvd1JLoAjcXMPoyafb85TLsAMqKytP',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RShDkVTDPQHNz8CiiC9YGvQNqjd7n19TFs': {
    'private_key': 'Up9eAFTEtzypCDpBSTVWaMEeBq8eZedeoC4yYHPGurum5Ebjxq6t',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQvSunDoHKoCG3gxjHtDSRMCmGon6yrZWr': {
    'private_key': 'Uu7MVsX8sKqBAzgcvmvbwgYn7zfyq7KHvbW929zkmUpMD5JLq3Yo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL7xeym2eTxWmk5cWdtT4E73cahiWER4Ui': {
    'private_key': 'UwycACqLFqJu5GCDuTncG5ncwp978krwZzKJJNzbyL8J4xt9eRTm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQJD59Qmqazg1ovE3i64AZAsgybY2B8Bsr': {
    'private_key': 'UwfWVERxViJMQHGvti3tpSpHn7EPnvVxwdkqArzgMo2Cgk853TCD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9SWYBqr3fhYXNhRZohJYrAnv4zx5gGfJB': {
    'private_key': 'UtVwKnNZhYY2w4EW36vyDX2dt3TyYoaPK4i8teMjgcqAAE4TLzNo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKpzYgKDLshxFeMPbELb8qspCt5kGaAgjR': {
    'private_key': 'UuUNPWRF8mXBkaPSAcnCRzjSDNBtPyKVusxLYMZwCdXwvxTW6KP5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWPYuzhQBrUohr7FGLwBc2mRHo9u96D8qb': {
    'private_key': 'Ur9oKUvSec27gPWVKejEPFEVHMhdu1MtoXHDQZ6nVGTxyrFfuNiJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSpFF5GgGfTPMbnJ6FqNceTFjSmdXiKm4i': {
    'private_key': 'UrSns7G7kkMfixkgVMZspycQzKjyLYmmQ8nsYHRK43kfSZ9kz9pH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVsVouKknXNZku8nce8MubNYTQvinKVJNJ': {
    'private_key': 'UumsuufFxgfte68sZNmPErdXkZixb79czLU6sqYwByNdS7EiCsJN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAgy9V6uDfC3bCnufb9YHojRgDNo8D9sht': {
    'private_key': 'Uw8TxDwdAdMvNzbai8LSKDXWdMSeaWkRtKYBJccPgze7vLQt62Pn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXVJLPXazpR4hhSxhTLw4eYa2hkrvXRVZT': {
    'private_key': 'UvdEbwhKj4ULRRQCiBphj5LkC9qgiqQ1XHd6AZtWsyN4iQQ9k9Sq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REpa7u4epsNXdRMxrDoq9GFM3GAJexVi5A': {
    'private_key': 'UxFsBVFMQkZu7phC2QVFEnx2hvtKueDKHUAoCwMszdrvF7pudV6T',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTrSvevpmWo3NGX7KHGQQw5WVsL25ayF66': {
    'private_key': 'UwsfJcAth4KZnLeaW4hNHAFGFJy9XotsgoXKsX1Sz3xRmJKyCb8W',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVuJZ9oveegva5CyTj8LUKBYwhYpqDCjEM': {
    'private_key': 'UxBGAJxgeWut4qT5V5vBVpgUX8YP5G7K2yWrfiDviZ99FBh2sWqb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGst8psRQ948gvVnc86YjCznaL2hGFz4Cx': {
    'private_key': 'UtpvEFfZ1cGLbg8nytRMcY9tShLQ2RUoib5Hr22Az8PMgHJWJFH5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RU8G4DQ8aUEMc3GEAUWoTjqUdQqBeVh5HH': {
    'private_key': 'UwjYnhVrXiT7qLWxsB6MAkfkyy2qtTpnH9YKqtZLRxjT5iUpHJMH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKYW9xn1mpGbvsXWAp1oVXi4cfHnaTKYHB': {
    'private_key': 'UpLbkcwLymRnskqn91rkjzcNqM2ByfFjUhWrpQm1vwhuyVJPQbAg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFukrGjyjtggXgMVFvz69iQP6hGARub3mQ': {
    'private_key': 'UpA3wbt47BDCNtbQy5YXZzomfjcfUe77xcgficEJ6c529TrjtTA5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RK7hfafDqVcqKzy4JWpixPaT6UYnwSkFbF': {
    'private_key': 'UwSPdndfbFFGJ9y1AtwemXApNXBE6vduDq9VYPnZeDxRHmFk8BAo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQSW5ocodG6FAUspspdaf15X3ndYsRwbni': {
    'private_key': 'UqDrtpUyGPGZA28JD7wzQud9iYSnfwvgMeXcEsNXnvZSnSRFjYQ5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGhAvQFn3V574eJDFZ1mZL881hgpNfHKUq': {
    'private_key': 'Uu85CKk4usXMUU1oZTpBvxh3HCxsurqJuMyiy7iGeeyEeeyToaMw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBp1HpPZoL5PbnPVgPTJRR3JSkLjish4Qe': {
    'private_key': 'UpxqmHK6JrU8Syq2osKv96mwbP2Rkw9hJnkbTdJqEqCDViAEP9r6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVbWobxWDCvVoovF1FvRLe1iRnrmmXBd5p': {
    'private_key': 'UwaXFHSRxjtg8R82d3NumF7EqWVgK9JJNyFSohqDCypJUjSx75fv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RM6ifAsdFkUZvKJUDaUL1Qv4fTcLsXEAXP': {
    'private_key': 'UqmXtYqa7WPST6rp2kK7LSvz7AUgimMmsqDG8r6CR6LCFsuotNLh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWFjP7KaqFkXP9h5Sc4jzFFjWnNb9hiWfL': {
    'private_key': 'UqjfytyS1cVv4nE5JXjfpF3YSDx9NZTVxFF1nH3WVSuac5RwCeS9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRuNDwjkHR9Vueh4qgy1qRCXzDy3DDrm6S': {
    'private_key': 'UshKhVZEGUDMieLbTmHgmBP6KHq6mTTo9B1L9LXRn8ByncyPYsNw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYZvNK9qAWiNg97i8YbuzndB63Q3MHB6af': {
    'private_key': 'UsV4s3HJk6Br86H9nbKGsbU7nL7dzPUTihy74Xt6QR6T81zzGMW3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9wo3Tsb4UKMgumh1iyQTcLNxrWifpuhnx': {
    'private_key': 'UsVuQRUFnwqGovBG1VhFXiHZjMBqvRGhcTZryQZMfyvYrPXGeoTC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9doxTzyfUjVDupPVfo3LnwQ8JF8M94DAr': {
    'private_key': 'UtFAXJrEvznDcJuJ5Uu1a8DdWfHGHWNAoNZbNQPdTzUKE44KQ4Fc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMdPeBL8Nx7XLesTgQpKuEsUFdJJo5DUeg': {
    'private_key': 'UucAptirZw4V8Afnn9KLpTNaDmLnfUzsViCMHUoJsE4M2vfTt5ZA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCs2TQ3A6Dk49rtjSnBVPVzixHF4pe4mpj': {
    'private_key': 'UtnkSLPJw49kiVM2hNA6FvkCtk5MukZ4CNXSgn8HFhnZUfy9Eiyn',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAxmWXLTCJRABsC1eDtgjGBshtyE2jvTFW': {
    'private_key': 'UwmnPUTParxeMBEio5QZn5E9iP9Y2uwoHNNTo3uiaDpciGHPdbyV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX12UMcr5HMeuFHDqnAkWgJWDaFTJskm7p': {
    'private_key': 'Usdyi2Agox9N9kXQmyJR5RLSa59r2nTQspo44pNDCzNjnt7kvCP4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWXmBiixv6DAmyuoososb2YXWgpGVVzfHd': {
    'private_key': 'UtzHh8oZvfaaRzRPzXZGXWFVP7oGygc5iMzg4XyVVmVwV7Pe2iRU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBpreA6raqZbyyJWg4nncXhURaHK3FvKNZ': {
    'private_key': 'UwijscFz2hXLUXjz2y4VicxTkBJr7ihbcHVxeWJ8skowFo6Jrq9P',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPoFddG7YE3tFkmMHWYqM6rssqdVNhJJbD': {
    'private_key': 'UvMiy5nSuY2TFwEDcjDKshBAiQVDYt8hzrn1CSWQA7Ym99f74UWU',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXUqiXeG6RWQq2zYe9nkKeiqAeqLasH2Qj': {
    'private_key': 'UpuQubudHF1bzgAx1zW38ksHpggLKFYz1u4gFmvNLKb83x5eysx6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKm5Pes3dMeufkYkA3zneWsb93KnUBBbkY': {
    'private_key': 'UpFEn1Sew4Sh8xmJp5YKZpsan2JfyxxRpwuhaxhDqTTWEXz8QDiZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVv4Qd6vDCiEjes9tYkURDgzQcnbcNyXW9': {
    'private_key': 'Up68i1XaniuYnkpAFiAxFgxmXA4xGXKquKhGmVD4vhVYQhS1KUum',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RC7rqG1iR15mEP6DCq5ScrKW6MuZxXuV4A': {
    'private_key': 'UvGEaTW6HhYjQkz5HT1B775nsvxqakxDFKkvRoRwVTYc2KL44gBH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJmjE2ErsgA6b4xkfqtgHpn4KxsuGvYQTD': {
    'private_key': 'Usyfo9vZM2taRo3QXFFwU82p2PoWT4LJBiT7C3RCWaiLtaNvKwTa',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RM9VuHLBWngCSjpo6u72TiUDr9kD3sitMa': {
    'private_key': 'Uvbr1WXPx8NJTmaVGxaoMgJbS6wGCDR3jpv6MkobfZp1AdBTrBeD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHMJcR366szYHVmbpTqCL2rSg2rEZWNEeF': {
    'private_key': 'UsLBJ3BWkBZKcob74Kmm2khDT7Wa8dGTKKUmK4nQZZrCwX6fRTh8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNFDUd7SeC1T9f8w7oCEk7PHK9WwL7J8sk': {
    'private_key': 'UtjwW1gLoNKuGdWVsUK3PvxXqJ7LcbbaZ2j9ezhRRuSz95o23Wzw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDr6rkcgxvFS4Gee6wZKEmEpaoA7qqmCo4': {
    'private_key': 'UxYrfyhxB4yP5ZpU2p5o89NQavNYRwGoMmdj9i7LtmR8xyejhXLp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSL4KCfiuJsr7fyKvDcRR6uZBkFaUttL1W': {
    'private_key': 'Uw7M7wa6bbzpAugFWpubi1u4DNSm6aQMRc72YZh1pP3YVikdSHnu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVfi8PQGCoAseK3ck9YtNwmxMmLzo1MWHn': {
    'private_key': 'UrH4oTxtMuo1fZA8ewujcjrnCbzCyFDbVYNQviwNCSHtoDaTYsza',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVCcx98GSpgjnKBGn4mChQ1NhszVCo4qKp': {
    'private_key': 'UrsfXhLePCLnDK6EbDQquwLZUh7JqHmhy1Ho9hoHYanpwfyZScE8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RW4Dc9YM2F8AphG3cvDBtRDQNK58ZQLTCX': {
    'private_key': 'Uteterv6JyA9AVagYC6c5nNJvYvvQDVEKEnA9RuBQJX4tJzmVC3F',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQpNAzMAmVQ42k9NJh95ccfAN4Wt1ucqgs': {
    'private_key': 'Uqif3uSdSY3nU5L5n9244GvrYbJxtvZfQqxRm1bGSywGog5Mhz88',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAHw9cFbPDFPBuPaaFdjY6yuPnzKd7ri4f': {
    'private_key': 'UsU1imxcXeq75QECxJjNUr4DPF39rEd7QpvCiCUrkXGnjSQku7xe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGT4jNwCGvXY9YmWNsUe1o5gDRpBnJ2NY2': {
    'private_key': 'UrRTuK2gPQuHkspGLzQwWq5He82CQvTZWZU2c2KuGD4fJ8tcdpvE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RB9gqsYRmEqWzU6WvsQDv9ueovT2VXFfto': {
    'private_key': 'UtmidAwE392iZkkmyCBi37unxTGSXuJxcW3HGahpD5UV2pZf9K1X',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RToceFS3WvJu5j3MRCeqYUadhZyjZcjpMB': {
    'private_key': 'Ur5c2aNitz7bgZqMpFj2hShdKqXoPR8rdCDKYnf2WALPeMA5RZi6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSQx7XkVE7SRUZNVTnLr9ora52dbCjMjrE': {
    'private_key': 'UtcyeTrsECojcdCANjronDPWPwqD4HqPe3atESiMCdvj2qfmwzJu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9yoDQjGzwv83RVp6gxXFzhMNVdNUN85P5': {
    'private_key': 'UujuSQfp1VyBmVU9zezPZsRaFLRwmqoAZX9w1hcDvuDfMVjqDgWb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPQXbRYhPVMQeEqXFw8rpmPi5x1Xg6ght7': {
    'private_key': 'Ux3HTAyPU8hVkLX2X24cpUXURht5DaD7qxjrrEurWDZuWc6uA9XM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBNYMBzg4aBRrF8po6v6H8hRgV5idd51ye': {
    'private_key': 'UpZWcgA9bUBXMfavpnS5j5wSLMUBUJGZQ7FMCNTkMkTyFTBbJJq4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFCr6Mg7HpfT133htMMviaqLPbPZxN7Gz4': {
    'private_key': 'UqAHtzDDBKDvyWTP18dYVFjGuqwn2NXjCFdSnAvjq3vecXbHBXyH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RExJBCrVy3j4q94ATKMQtGD3YuYspCPHdi': {
    'private_key': 'UrgFhjQrWBDr1JQgfz7mrzo3nWrYUEqZj78msEJW39HFWBYYcghq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVViaFJSevoNk784bpkGW1fdz1ctb1Pfcs': {
    'private_key': 'UqYLxQFQkwB9mB19gDfFPfjD8z8LPB4aDofjgfKxRmanXmhu2GwN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAoCMWaTcqFV7b5Phbig56kp2pEwg54vxP': {
    'private_key': 'UsSHbqkxVsvBDXZFc3Nyf4gRLpG2DJ9T7RGWCwG8QR657khdTgQg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RR64mkaVY2ZLxWbJwMT2L5gq2YpKGpNn4J': {
    'private_key': 'Ut846ZkxRDU4M37BNMg11w5daMa2Repowdo8HagZcMQLB9X9vvpN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RF2WLdK9RbAujDz6iZCChpmcm4mDZGB1td': {
    'private_key': 'UxFxWRTsTC8PRCCmictewaST8svfGb6vtNaTWXvKfrAuKgegwjcb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAqt6z3tBwNLqj4QX3idpAa8a8SDdL3ypB': {
    'private_key': 'UwSdt9q6R7xzHgz6hYKgcodmAJ3TcvprP2URUDy5xre25nFCeKZA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RF5s6QKcfnH4iCG9296zZNnt4gMRtNDo2R': {
    'private_key': 'UxU9CFR54bg3NKryY38vMEqTpmwAysCMySHmYfnDAv6LMfv9pk9r',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXzhbJBKqQ7LbVSp4DYTFY8fnwqcREZVu1': {
    'private_key': 'UrMBtS1ruNQhRAQgP6kA4F9493z2EEdhkHBrSMX6i863VuSL8oug',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAGCaFT79Rnueoh7A9bSecHUfERJvFVZVT': {
    'private_key': 'UpefRepCDMry46MNkWmM4PmeHRnyDLXnX6L9UHp8y2CTUxmgkaWh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RML7JrggsYiBivFXGUaNpddoTjWskuuZSq': {
    'private_key': 'Up1k18rMv2itEwtjMrfuvf23KTtxDP73DRfRCTPy2bTFpcfsE3zV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKRatszXBKjjJEau22SPnjmtAT9jFEhF88': {
    'private_key': 'UtGtXduoZae9nhQDXwx8hSvgTvSG3gxGCtuss3EeDkoAhWsq51yL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMg87HNMvkkfoPs9Nurc33FVvpTtN4EQMk': {
    'private_key': 'Uqp5mQ5jiLkXYC9ybmcZ4QVG5Ek81hSt1hCvaP8kaojPx687fdes',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAtnYsL6b5ifBk4gqmm3JyR8ZH8MdmGvxc': {
    'private_key': 'UqDyhYkyXd4vcMinRksBXEU1QQhmpaN37guy6ByuGGwWWeVFRATi',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQeTcB92UGEvMiyhzGsjJAJAEMXKj3SBnQ': {
    'private_key': 'UvigpbSXHpjBjXdsdvMHXEppyMY4X9WNw1utjgMTaFTMffeoykpC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRHC1qQ3U7qqwS4QFf2wszerbvXXw8r7W3': {
    'private_key': 'Ut6WKZdsXpxMG2381sJ7jdojavfDK418P4fXctY3Z5iH51uKTXuR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNJzodR32d5YaeA3rB6cjwLXvJw8bejfgB': {
    'private_key': 'UwQdo7VS3b3oLc1qrr9FmviQqxYMtqVUAKLczTYsWkURswjq5LYN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCpdz9WDaHabbrzrmjxfJR1rR1GDK1ULFi': {
    'private_key': 'UwhPiLfh4ohrLtR22TYm39CZ3UZTxFjecaGd1NgNGY3WxAi6xMiW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL5rFmaSsoHVReYWqgxMivDoXYgJJeQeLV': {
    'private_key': 'UxD5zsKSuU6132RoxVCXz6xPe48o88cdM63BPZKfVHYQUUnfDZ1Z',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFxzvASFbdTTKiWj96uMyecz2LGuCszjVP': {
    'private_key': 'UroU3EoDbCemzFTEdrfY9SLoAgWYbsUYJGHQVX9LxKVsmZopuPf5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSJSDoAtsh6Q13jacDBfN7pyPxBhA8h1zA': {
    'private_key': 'UtjTvc5UTinsDqsTAYHbhNVvTRFhs7Uf2tKZfyMY7DwBaHBQQXSh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVsYSzfu5dgtBYWx3kEyHnQuo4ESmQz42q': {
    'private_key': 'UsR87L6DybTck4b4SDuaspspPessXhHBNv9pr6uX7RM3grVRR6Co',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRR4gXUkikpx4Q1d4NWXWPA7dpjqHZnRsF': {
    'private_key': 'Uqiz6pm1DruQfRDuyonfrtnaGH9fPtGypzxHKRgUWrxF3Q4jNGSs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDVKcBjZsP4fk7YmqFsLhqYKa1CruLfQbJ': {
    'private_key': 'UuSew2MTxLkYXvqaVcv8xxpQXhGriFR6sJJmzvbved6N83MpzCgP',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTCjwMrjYSYtgMzPNCchNJMCXxB6qCFgBp': {
    'private_key': 'UqtSHPR2wsYvf2Nd8KNvfedq5RnjrXf7sEpmQ8MLEotf9f1LH77y',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RC1drSzZkP5beh6bixPwo69kEA1SiKmW3n': {
    'private_key': 'UwNc85qw63jZFyzMzYoFD9btRD9yL7iMC3973DN6c2vVK7qCLUzs',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKsjWqMdkqwn6gG4qf3Cxyb4axeMJdW3K4': {
    'private_key': 'UsM94nRCzy3zC7JaUm5KGQFFakBVdLxQbHPsf8LKW7RvXvpwtmZ5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REU6ZCj5h23zgyWzfnAw22JXa1fqbktEKu': {
    'private_key': 'Uu8pAxEq1SWbMubUKsCKaGWGb14LitaRDViPd1EkgrPtTwtoPhag',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REWpaMk3LYYZ1DvRkDneAM2xjWWFVYeHEz': {
    'private_key': 'UtD65z4A8D6EtZdq6C4vCw73QzByAkf9uRTCzSChFmLx12GEdnE6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRJ6HW1YBdPFPNjjhNFD74Kc3pwNo8gCUX': {
    'private_key': 'UpLsTeFXviqonDnnqF35r2Toa7q6h9iNYUw8dS5kV3peQ8GfBfHw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNCUQjS6SgyqZsXyWQGn7WXhLeTcR94yxA': {
    'private_key': 'Ura3DPwRAt5g1iG2HEBPDrftMFKUxvQA4tY7UQNQcgavYJzaB1pE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJihy2b3m36HHa9ysL66NAbPhFKQ5feHLR': {
    'private_key': 'UtXy7dpuNNwthKwJPLkJ5ED7AdB4LpAJnBdRZA9UKWP65wTPgeSG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REmJCCMJFdJX34mV26h4R3jWsZeAkaYgwX': {
    'private_key': 'Uqye13S8m9Z5wEX1QvLbiDDs73J3t1XEPQCxhq9f38n6PZ8Mgd17',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXAku56DySSBRUGf7UPMSgUgdGsi4fXTAN': {
    'private_key': 'UweQPKDeFQaKRbqXnfdxsGwhpXGBGWr9jrbz6Behk34rZQjhoXuG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXNk1LukwJ7EQLbcVpXPcCfsYgECgnvMp5': {
    'private_key': 'UqycWD2zgEVpZewiEdHpNG5MbZM46BUR9ScdvqppWzJ57czTtXfx',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPoVgWCJGFerfrgoPmtdwfijcofuGDTtKB': {
    'private_key': 'UtXezXa7xJqcVXBPG5ZXF2tPu1Ty7y5ASZuMJrJh4THnnmJybctL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPfiwyquTzdL6B1CjXe7eRkiSynosSBYPJ': {
    'private_key': 'UspaiPHkcPEt3dJv5BHHQxQ5Vo9EGtH2pNcrFhZvGkJvk1CN7bvu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFM6aaM6MU7er7Ao9edxfVfVWWGjKbBKzJ': {
    'private_key': 'Ut89Gnh41vizs644XWMY2CP4yaUwYBvpGKkcmiSFWt77vFEk2kPF',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYAYHmSW84jyHGWDr5J4Cu5nQzAqBTs2NV': {
    'private_key': 'UtGVfSGHCRsJuBoKMZt9kRj5QbopEzhqhj7nSvurqroYZep1A9oK',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9PBa6gSS6nAvZ7APad4fH1uX6xViPjKcH': {
    'private_key': 'UpfbEAyjKYAGMDytnf6Gkmh2ThDPkKVugWQ92nUHHFYxCKJGq84v',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGAJjYAJ1zGa7ixXmsQT2ZEUXMadJQyBLa': {
    'private_key': 'UrLkyyUqKs49WPA8BVzeUL3a7dEp6cj15mBEHQhDrJVUmRcv9Y6s',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RD7CZ5Fz7YjimvFLUJdkB1aEW74ZUWCg8X': {
    'private_key': 'UrBnnhYHrEdtRN3gVvvqK9V2cWc9gLfnKYrWqK9NpvxZAEeUqEdE',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDNv5ws2KoUsiRNYSPnKgjRRFLxv5eJYsM': {
    'private_key': 'UtinDYDMjfM6apv8fvzRQoignWJkDjygDx41zvYFVwL1UDvDCcnW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQNbodo8yYxoTmmvwecNs4Nq7GXEs7ZaM4': {
    'private_key': 'UvgpPZNHsvTwnSx64BBvvordPxns6JDTcVoMHczEBpPinv9EaDhG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAHA8SMpZcDCDnMAqX4QtcbtYkmKrzogHN': {
    'private_key': 'Uu2zUCCFCyQDBtH5eQsgoZvEG9F16dqWsw3wYSfLx3GhQtb9S8Mg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9feVjfq44rkfkMgSXgzGwTJiXuaoR8gpe': {
    'private_key': 'UwiHVeANneLQq3JqESVU3iRCuic2jYg4rcL5PBFjsJrSNPEqfFz5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPafdpFP73ZLdZTSSVvuLNrRuSNEpUP1qU': {
    'private_key': 'Uuv6w2HKMuB7Q98XStJkDd5guDNKbR68yrUb4ewDkySfNEXjTZ4n',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RM1msbWwsYFN4d3acLnQ8wNGMpmQXmeASx': {
    'private_key': 'UrB6UEmoYhYR1kjno9ZdYgX3HuZgJtNDfaPgS6fdVCNcSxiCx37x',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQP2GJcbHAJqbgizX36y2Ugb2MofXi6YTD': {
    'private_key': 'Ut7FUA2Dyag6GPga4hAsdbipEcPSHaADT1ax9hjQ8ZvFvR9Rpyny',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSQYecP88NcYVFWpCn6YBk1yWeYgrQZ1eN': {
    'private_key': 'UwtkPk3wH3Ub3pZ5tCjeg9CkwiMkAqhsBLJoEcDkgSTKPfRKeXSL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKkPH4z1dzv3DHr46A9HD8PFx78taqCHBc': {
    'private_key': 'UqD59YNtXCN8DVqw7NPECNPDsVSV57nhLdyzYgwsDZbB4wZEFca8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMvPVx3EoACKujPvoewdqAkPU3inkKk3wc': {
    'private_key': 'UvvKURtAPptghaonNgipZXjDposBL7gAfRMHBmx4RXVod4NVDJQ2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTddvjPACMUDnxHYoan11hN5hvo7YQxqFL': {
    'private_key': 'UvDv611AfGt23K9hCwwpWJssNMnBPtfkvNRy8Ff3BaPjSj6BsXyp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFPhASvp9Q2MdNDYEQKTp3K2FGD2aJ8FKd': {
    'private_key': 'UsJNEqyC2khx59NLucANDnD8xLPbm4X5yogdYJHt7iApCtXhfx3Z',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCFY9C3KHoz5xsUek4TKStHu4rU7eDvkw9': {
    'private_key': 'UpENYrhmmBEjvRNo5et1m21oh29vD6SeJgXYCa5aJAAnYezon6Fe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYE5qzxMvZu6Lh2mTaYWfftvNwsk3ZEdJe': {
    'private_key': 'Ux1otMXEH12oMP2yafWVJo4vMkZ9hfeX38mgmsFDftRcJRdxL45P',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWDDkssPd4DW5dGnTWLAfmABA5D2ET9Bgj': {
    'private_key': 'Ur7rtci351JedNrtuf9oiGNaD4unoAkHAv2VFZZJATJxm3QpoRhm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RN9vNG4SwgisbqcF1zF4gfRKbxdf6dgKm9': {
    'private_key': 'UqfxwcvbqfvEHhzaENuZgjarXvhznBkbNWrtqQNyEB8i26kqomA6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL6ZTa4MqZR5ikYuKGtsc4VcMERXAhKv3U': {
    'private_key': 'Uw7FvxAv1TvurtBZ4cJ2vvyZuBuzpsK9qEzGo2t2bSdktVKomFai',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGs8M67qfpWjrKbbKQvNUdgdto3Cq2HWP9': {
    'private_key': 'Up91WHNfiDvgCpT8guNZbbmG9YzJ5JSoz4x6VnoQM7Jhbqec3bQo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9nC6HPf7WAza2LjRtVMSPCBywgZtRRkmQ': {
    'private_key': 'UqNp6fuRVok9vuGjYucXCyMgrSNLP7ZHPHdKXY7iBBNnnLJyumH1',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSrMoi5fq77Phhk33w2ztgZv2fxHhZmPWq': {
    'private_key': 'UtzVGkAvC8AKCZqRoZzjWZht4Xx7WHzeFFrqkcuTzo4L4iRt4ZoR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHetc5qcCzUCxbw59QV7zc6bqvSSHpxeP8': {
    'private_key': 'Uqjm1yQ3MYipP2ikcyZG4RZLEKEC2uJLjr8Xchqq2Ndbe81wWwdj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJhcG2Ct6vrZHr9Scnk1ApJRpVLoJjDruC': {
    'private_key': 'UpuwrydqYbgQq9whifvytgWSWXtRVs9W3ovZG86UZmZxPNRCqpNG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSTpf7KNcHwe8JHBRX7CcJZdMaSvUBra6W': {
    'private_key': 'UqD9dLPnHKhnZXYN8fWVr8YjYzYXvmfCHxSVK5qU8Cim1bGVS9ih',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFcuz415tbG1AEcAJE11eV4bB4k8WiRkaD': {
    'private_key': 'Uu5RG6PThZvTE2L2rNaNSpEKjCnx9wDrwPjJaXGgTuKpkVMhrQiS',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYFxFWjn7Aw6T5p4CB2VrKGoUZtQMtHbYS': {
    'private_key': 'UpsMRJPtixs9STUbc24SSxDgE8D9tDvf4XJUcLJ45vznbE1fMEBT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMUbBK85Ku9FPDhJeJ4k8jGKnZAo6KaEfV': {
    'private_key': 'UrGAR86cE8LUVrLwUZLCw7Z7aEhwr6SfF2SYHC4BrLCLvmnPH6ze',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHFkKfvL3xurMaHaqQi2PzZjEWcu17FuLD': {
    'private_key': 'UuVcRbGK8dV2kje4ZsiV33CqWuYo9y2Y2jnCPZX9uXMvuqimZMtZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVGH1L9XKC3FsjXse7szz4bvxnrGCfmdDC': {
    'private_key': 'UqrvXdqNL1xS9DbXwX4ihNm9qnxWYgyS7nmwF9nahz5ooTBL8Lhw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REUMFLZfFMeq4veYFnGe7iLbZMy47Z4kVX': {
    'private_key': 'UvAw5ECnu4ufv59ReojszkDqEQmPPffHtp3y5hkQ67hrFxc3tvcu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTEkZTtJZxPtSbw3VGjzz3SvQQpnFRWQ9L': {
    'private_key': 'UrGTEYAR2DdmdDxjF2AS7GgY7cqt7yFu3fs7JDqC94W3X92aWJ1T',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNnxMgy9iVGF3er3TYUoi92BWvvMn1ZMNH': {
    'private_key': 'Uvz8NKWFdER7EgWqsKrJ2bZ2SBbJrV5F8CU7CRxutA1UhogtZQfc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQuLezCCuNthXoNPkVNp1quUGZv9rUatjK': {
    'private_key': 'UukbMoRX9fK8RP5dUk8QpbLGQUBVP4E2Y1ty1tmoKoZqW9R4ZPca',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDRejANpYngz9tqzRK4h3xtii6jPHeS3qo': {
    'private_key': 'Uvp9nakmJYW2FZVoCQHDc6kZFLH8vYGFgAsxQMaqFoYWvk4WoA6V',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWSqTri9uqhJF8Qi1B1WDTcH5EzizpuyCB': {
    'private_key': 'UsZ4D3TWjpz4XdF43sjiRKiRNJQ6phBCjHpwcPLhHELqkjDvUdUa',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBCmarrfftsFFAyqFCrSj13xmk3q3fgdfX': {
    'private_key': 'UxLscbB8yyD8uNuELLaJNtVvN73c542mrLdFaVoxZnj1W2b4522m',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTsu1MZxiMzS2D4gt4qywZibHckdJFtknQ': {
    'private_key': 'UpCjZiQt4yte8PNGq87EaxefqCfkmMi6UyoGxgabCuDSgNUvXH2t',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSzwWjAdeQyeqLrW714kU47yZZ2VnguwJi': {
    'private_key': 'UtMdJ7iQKZ1mDyFBj7R7wRYvn32hNY58pkGzbuWFwYMj7Yni3NeY',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBTaoHb29DAxBneymWgQN8hyisAYEu57RG': {
    'private_key': 'Ux5eq6czX5cfm6wdbdAmuqgY5mpMxJSYhWW5bPNgPcKqvU72f3pW',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPrzda8Xtvu1qv5VzpNtEAriMD3Psw1JxD': {
    'private_key': 'Uq2zdnguyhrXsXkPK8W3wQGMJFhsqFeV6zBn1fGAMwzmHitw3ZAo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMH9khRL8trUyNbbEcZ4iNuUvDPxr1Aomw': {
    'private_key': 'UwAdUPkRuhczoe3wTAqN7rRnTGwx2QH5euya3wtWebTHWw7kTMgb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDw3DPaNx9GGPNNctXjV1aJoEbvLioozaC': {
    'private_key': 'UsGSH4cPgzmgTz9N4XUUD2rMAKQvzFUFmma8QdbnmouUYQuyVdB9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKw8UtbMygRti4Ph8dSsqAzPAm2CgnH81H': {
    'private_key': 'UpncYnRBqkLb7CXN2wMvZ4PFv1egcD3urcKm5xKYHscpfMms4aDA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGM7z67RFLMJWZTBbn5mwhuDZA5hQHAmjv': {
    'private_key': 'UunT9PprbRqQJ8UbJ54Ur9vAbQDyPtCkEaJQLJ5tzXvgSWgd9fiu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFuCWYUyGSFVPDU85iTiqqcEgQTGuzJmm7': {
    'private_key': 'Uqq82UrR6XHMtN4DFxumgownkB9CJob2Akpm2ZSQx8vJcCSD5ByC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJmfLQjAp7v6sdarRxGwWYSDMFYn8Re3AH': {
    'private_key': 'Urdrn7zL5Eih78eHKCjd9mNksf4enHFj1rYVGLgFzMm1jDRcjFMz',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9sUTGUCcX2KuRQGfia6wegnQzqgo69mBz': {
    'private_key': 'UvwgzyWdq7LZ9KT19rncxkkM9nMa5f9JEfNqSeSpcNQRT5BYFJuX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXRM3T8XZKwqGtS7HRZHgnCHPtHccELfwP': {
    'private_key': 'UrxZCuPerEDZjrAyLhcbNpCZtoBCSpLirkkAoTfks19mTYPpMbK8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFnd4wMWKunh5om937KZCmBFJY8PaAXhfs': {
    'private_key': 'UuEzQK4kebpYEuQ1SYgdeEDLt8ng75WFh1W5oZF8WzQUsz5pdDTt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUW4iwKjy1mwdNzrehEG1gMd8DUPUzPT1H': {
    'private_key': 'UsDg1BPfWs1gNia2z55178XsNdMUKRcAXHLbqusuWpBCcNfvjXFd',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBhjBUywL2nZz6hX3AAHK9imy8F1zAX1w9': {
    'private_key': 'Usf8pAULSetPa1yEiQemH6E8mYJmo2vpPA9QSF13FnvhfCv3WRkN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRLg8U8P3fAH1kuER5ZxxNFLY1GUCXQ5Yu': {
    'private_key': 'UtpRhVMvXukvAusfXWoAFkE9vkt4ejZAwmPYNA1vtjWgf9F6SPrj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJKUjiF6j8zY55CVoemde9eDRJ1Bayz6i5': {
    'private_key': 'UtqQ9LSDD72fBZSDTyNLCjUyF3XegXPAD591itwvFFfhb815LnsK',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDiKhrneU2QnD9EuLFSaHvu85oZ3AGQTJM': {
    'private_key': 'UwdNtkquQRkYjCN2BVfNnbQA1wG8QB51mb1zVygaeB6Nt316sjiM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RT3yb87GgYVE7az8uaczsGPftiiXbDvzsB': {
    'private_key': 'UrYVSi7tQLJwUcjciKpRNwL7fhgMjUX73f4f8sGKNTtbACqtR9ck',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RY7QVbzraovRagP8U4f1KvnviDxW27pXhx': {
    'private_key': 'UwBXYAzqTy9c7TQyZtzHRR3MeVZzvE6hXdFVTZ74DE6ujpUMzdU6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCVqxcQC8VMuBQ392R7Qxwz5SHZzfYbwVx': {
    'private_key': 'UqV4gVq84BfFoL6hGwkXebWSktNEE6mBPGvk25GNtHhte8J9FbE9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RE6VUSetZDW4WFURgLaknBPqo5ceEsE1Ud': {
    'private_key': 'Uvu4ZLKSrMHgVhuAfFARxDtRcPtEMaiSQT2JL93Haa9o5t25GWiG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVZN5R8hzHtpmHdwPPMTCyRZyYV4oqPvew': {
    'private_key': 'Uv41Vd5FYsDLnsZ4VypM5Q2fNSbYwjsskuRPp6GQCdAEYA2JDsUL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQWjgiZg6K2w4M17uegZ8jZGftXxuf6o56': {
    'private_key': 'UuYGHV9Hd7rGUH4gVePdRi5d4d45WjVg27LpGogD5zbuDEE4TEtH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RF6WnZwC4bhkruPB3nFo4DiVbR4rBPuGBS': {
    'private_key': 'UqE2MsVa6jKw5TxtsQC2PHZoFW8i42NdTeirG8YqhgdJomb8BxvB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAitkifyB1Amvd8ZgYSn3UXRNJYqUjvdUh': {
    'private_key': 'UppXFaP2j9TZbCDbvhSvFc1jsHFdcMAk8b85tp3Cra6ggTsbetPu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RC6jLKB93sQPu9yNQhQ99sncbTnfQwQz62': {
    'private_key': 'UxJriFuo9Cb4vJmvKfzWKiKxEMRdMFzK4fLKcB7qNGf6Pvi6Gc37',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPB7nuMzspmX1TuyZHFeeKdc51ZeHNJWWA': {
    'private_key': 'UtehnUdpyrv6VULeVaWGgPJgMrPP2CtqjCMoqFKXAhXPq1xVkoo5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQ7gSMjG6nE8UaH1SHrxcuBDARBKmiBTVo': {
    'private_key': 'UwRn96ESm2Btup4k5WP2U9x1RaPFZFQTEiwPHpa19YBSUzY4UegB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAjWB7MtLxKKGf9Urse68HXHtpH7duP3od': {
    'private_key': 'UvXcL2wLBnx9mPMBEhUijRPT3Ne4kunKPtcfVTo4i38pScnAwtbJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGU7iviESriBPZBzDNEzJz8pHKWTmd7WCF': {
    'private_key': 'UxXMQQG7Kt4fdoQUDrmBEZR5oWchv5gv7FtPWVgikTf4LZgNUaef',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCPUFQspXoKeQRUe49zyCk1zVF74jhN6Z6': {
    'private_key': 'UwYxyVAKvMKJuUtykk4vQPLhrVbrj7LwVz5FcKiqpg6RkH7p6crY',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQdqCjvqonGZRW4qKTmM5FoN3utmr9iSwc': {
    'private_key': 'UsQDu9cdJ47ow9LzzijLNKUvaQJNf6jv9QZj8fHdQytYgVKp8q5K',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJcxjny86ufTNKDAFhwmVTMikrME5tB3Lq': {
    'private_key': 'Us7T5cMvVZ2ikN9iGEnZrYLMgFfPwStEUREmjMpcuyguLMJfVg54',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REbhhN2S8aTsALZZJ8Yo5WHnfSkCoHuzaN': {
    'private_key': 'Us385sDyVtMCrAL4UYE1SRHiwJgY1QQsxt69gS95D8jJNY3uRLuj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPJCTgu2cTf3tUssHtwXWyEJNPXGZMh5AS': {
    'private_key': 'Uqe9mYKk6uWjNJiYuFnsYgVMuGpUv517wkpWxdXEiEk9KvQktoUe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGcyAkbpTXrNNaqNGHCdvo2Paa1HGtbeTv': {
    'private_key': 'Uw9frG5yQ9yvTg7HDMccJp6v5ttNVp2dDwubFUPPZp9JE9cNbkiT',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGRm81yvj2YoK4rtZfUFXJnYtjP59bFtqH': {
    'private_key': 'UpbTKPHrsqsU8ti5DHLdWgACZ6mgaXVGpk24ZdWNdkD3EcjGwmpC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RE2uSWFpv23kRvYpRybKpNpmzgpnSW71tr': {
    'private_key': 'Uqw1D45JN1caPcgtMqTPUL73vjxvYQjtQjQyG1e3Kessyd8CzeNo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCEUEKXaFtAH1z5D1pqNr1R21kzSSSiY7x': {
    'private_key': 'UptSAADvQzBMGALpzaAA7JRLS7mHaGqs8qWx7UcDEw3j1yQ9xWd8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSdyxFf9tBX2N4bbJWXT4u8BmnGuQAbptq': {
    'private_key': 'Uu2qrJ9geGBY8WpFR6UGGFpWScVGtPS9mtjJE5w9vGr3CPEWXbjG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGetUCyZmp1s8Vr2nxMYJXDbRkRTgJcmUu': {
    'private_key': 'Uvoqbj5qcmC2mkq3Ma1uvN31JUkHCAzMn6xG38E1rbj1t6nWqX7U',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RE9nuPJ4dXBsvHmkvUBEFLVaUCemRPkcbZ': {
    'private_key': 'UwCK2yaaWnXuDEvHozxTB9NeyE355KAPmfhGzSh8HmPzeikoqruA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPHQRotnWgcWHy6o9Lm7ypZAus8Lw6evrK': {
    'private_key': 'UsEEpMtyTNZUG8236JFuGnFSQdNYNDPmMhxhLdgbH5T6ZMheMFY1',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLALFepyNJ6xKYeVvUiMvgbRFYuqNVP2vi': {
    'private_key': 'Ux5ArCpuzkPP9qdFB6kTofHQvnsUMYE3nX5meMCRg2BBjkC5tTY2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RB7PiwtkFCvabHAcPWzQffGKGYTuGzHKFV': {
    'private_key': 'UpHWoP66XeYkPu9Sjf2QgTqxFB5FSVEL8Qn4shcGDaSiEiQohrxR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNB4yT27X7uQVyHZMZipnwuPMhwMFG97Ak': {
    'private_key': 'UveVA44WiEgfUYeKACRKx89Wu7AvKDtuBhZRHktuFe7VpF1N9pFv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWsMWr3F3771NEKT18XKi8H3i9M9ABfVN1': {
    'private_key': 'UwJSv6zcdvEiSg2XQJmzNN8ah4DYEiFGCnPEvdbWfUQc7GEs7ufh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGJE1him7XLhdmTdjV1EwELXA4sHoPrEgv': {
    'private_key': 'UuemfEwEpGX1jEEgcjuKhf2mw8wXHLyMhg7VcgHjEiFcm33Nsmmj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCCYsqqA7keN7D5K8211RFmmaHYfMBSgzG': {
    'private_key': 'UwhijF7kmXwjDgdDLrKTgjKvh7xcnbGTxPbkFENvCmjkZF7EtXG1',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPs7iF6szuuFLnU9Ur7ZxuGeUgTVXiKW6F': {
    'private_key': 'UpNVTZUJxygZtbbWkGU8jHvFhDDm34ym85VPkpKbPPkUPMPzmh34',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RC3Wjg4zPfz37CPodgdmw2ccwSLSV9kXu5': {
    'private_key': 'Upxs8RpvzvJnmnskTQEmtzNDqE4GZix5zKxpgAYtPvTzWyeCcdVX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVLBkncc3u1rxX7SxVgwF3LYMbSZdSUCWS': {
    'private_key': 'Uwqo3mrVcpz7xT1hKoQo9UyR4uSUmMYweFEBW5yoCYvTzaYTDdb3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSA5kwLyDu2JR41EYLd7EFJFEtDaAUYgxc': {
    'private_key': 'UuLEWQun5Rd96M1Xtozs2tVTdFm79sayut6jei6ewrnffQwG3Fr2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWb7dqWaghGx1LiauXdT4aPP9CsvvSESaH': {
    'private_key': 'UtKGCwpr8v1dpgouxFJR6oCq341zuQqni4us9Tg8VPQfKEtjt7JA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKd2Z7nsrTvpcu5igsq4qBmnoJYZRQLgQU': {
    'private_key': 'Uvk1MmbFwCioDSNCohTsX8GG3g4pDWKt7eg5cwqsvEEeEE6MBsJZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RD8jSMv1xTp7fPTmNNhRbeoBuCXEJjG7Z1': {
    'private_key': 'UvXTMpkBLUtNDTEsMqYx2gNiwK1a1VYX74oid8cR3kJFAKL1V6CS',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWN1YBhsuw7bbP3meZzd4na1A3FbJNjPQ1': {
    'private_key': 'UwzfmQY733WSGf81ajpNMzh5Wgzy7XXmPZRwpue7SHA6t4PfXGCY',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRACe5hYEdNjsjuQEFx56cF3ui7PSBSWCh': {
    'private_key': 'UqdXbQyw3h69kGKhAsD9g1qfEaCR9AY9mDWDpWFDK9hhGxdV6k9s',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGsBxRtMDbdjhGaPpe3V3szXWe1YgyezbK': {
    'private_key': 'UspntvDyGgCtBbjbxrpP443QkyC4jCeq5UCYBK5MYGqHDaRQzoxQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHktZdGKXF13vEPgwZQ67SfaBzKst2zszr': {
    'private_key': 'UsG4YgmHuzoQy42Vb4FpV8x24meJDPUbHmsTeMAJg2knt3FYMuzM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWYBNbsbjFgNPZUbTu7L9RSpEDYyTb8T4R': {
    'private_key': 'UqaK9sq2Gx1hCH3E13BmMxFEtLiL22Q9a71xhtetWeajGuz1cmDp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKvSRKwe9D9SHbP1dEeZmRG4t7qvyeVp7q': {
    'private_key': 'UuZGyMZ8eXfpuES4ZjD1cscCeDGyuAcydq8i2gazKzpMs2KvQTHQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKM8rwbHKUbTNXaGn53wiDxVSH2h96vBdo': {
    'private_key': 'UsTAcndx2T5bd7pwcGLtFMNSZDzteEENDNnE6W6Mzb3xRtt9Eo2T',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMvuxU7dFB2YARosm53JpshXNZgzgpvxxY': {
    'private_key': 'UwFCsusnbhLc375x8HGpVJfjyX75NFvcUWt1FBouzuNov2UhhtR3',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RP9FxfiTTxKujRj8RbBNnatK526NZcFUpu': {
    'private_key': 'UwkivccHNFawchNX4WnRt5362MhbXUqauWggUvkTEFQU7pp1cdgq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RP78kUN6etJRGXTRtxRsUc1pznj3pmh15L': {
    'private_key': 'Uws5ceoZVgWXD8RsxWqxAPhJomQdrbduNWLcT1DZAD9ABiWmaj6p',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRHesw9ycD66JBYKeDeDUBU6V4473ua2Vi': {
    'private_key': 'UqiWfKAH5eTEuGqWf5f8QjTLoDjAUzJJ6bMfhGWy61XC8mTeiKQB',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRtRvoLFCyG9h4rpK4keLGutwGTKsuVU7m': {
    'private_key': 'UsnLZY2PsNK7LTesE6mHRbSoK34MGZDok7Q2KHmaC9L8qNDoktkA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCRZc9rkzrmxsCJRNabnrmuv77XC6BjfGq': {
    'private_key': 'Uv6XC61mLowcrWdVJBG8xqvYg13s1B1351e2WvTXdAZw9qmocZbQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPvZMNuAUbW6gtyev9pk5MHqC7HR21VWY7': {
    'private_key': 'UreiNtRzGySQ5CTKr3pTAnrX6QrjEUoiMBb8D4f5hkDQuT76yuWi',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RReQe1EV5KBTFb6eK2JJwCNCFwqKY9zu4K': {
    'private_key': 'UwK3W3vDNcGb6V8wSe9jULa4XL7XKTQGGdATq448czpKtPjSWnha',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHb8JkDU5DR2Sz2SQymPureexEdPJGqU8k': {
    'private_key': 'Uv2cMGk5f1Y8fsgXu7VygnncVAHAy7KfbCZX9ihfuZxtbatWFpq7',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGoqN6pSvdH9is9A1omN1Dn2QxhQWisYL9': {
    'private_key': 'UxLYYryyX8Wg3iP2YR73su8owfuSo7hPo8ThDuyKQNxJ3yqMfkjq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQnc1vyA6uX5Dauo1iEJoNiTbqhUD4Lz3S': {
    'private_key': 'UpcoTHvYq46JW4tPrgxP6XPU1unm2RDCGhzMYwyg4NJYG8e2LLqu',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWqxUcyafGjFnyihyPw2asPuRzQ8iznE1r': {
    'private_key': 'Uuq4PX4YHK3X2G7XKujREcyAmm2hn7Y2BGCZeeXpXaH9315fsU83',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFymzNsvC3XwxVtj5jHnQh9iQ47oogg7fe': {
    'private_key': 'UrSDBC3tpBGvPG6iXX7ARifxuVn2yuTf2Gq3jkrCpgKEsACmkyQd',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJaRx1pJzVnwxEzsqPtKmbVLphrKgqze1p': {
    'private_key': 'UwjkfRtLf72jUNERHHWQ7t8Q8nbDepgC9unKjmtE3otThMbtjbNX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RN6egeykXCVRUKxAWLPBXPyka83GtkCaLT': {
    'private_key': 'UsUWggm4bwFtNrkLc2hMNN4sohsVburUeA3kA6TDSppBkns4Updb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKs6WeSwmN5HfeBid9eXDdceuhZv6oiArG': {
    'private_key': 'UqJ9uHhGwXZ3xwZQUfBb87zwvY8mLEtVputRuzMCRQfExJad2NR2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTE2m9Qu8CvX5XpMWMDqkWHJtmAiBpQwzZ': {
    'private_key': 'UtNWWwLL74jmsXstTKVDBSA2qCc6GVKFni1Wvtydyu7FaiKaJASe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPaiZ2ZtTp6K6Wo4Dctkw1ddRhfw4r8ttA': {
    'private_key': 'UwLj4XNR8sPAdY6A6t45RrGBVTtomEqAYAU7qL8MgE8Tw4aDLShq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJtK2Ak4Jt9JZYH6p76RTYbm1eZovpDJc3': {
    'private_key': 'UuckCW5SeAa8cSdod3eFcJ3kSzDposQCURV7y8J3bzaWMJ8fsFBR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RULuDHZEAz2znhYqwoBeN29usjJLVwMyTa': {
    'private_key': 'UqX5jsMDLPw6phVWE2xEGP5p8h85dkcAZ17J8n8qheS2xT1vaeLg',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL8FGK4rB55d8FRYFU2yfQnHBpRWFbfX47': {
    'private_key': 'UtRojzPYbQsjyQSQWJUnmv4JjkK2HGVpG739Yqkvt6gLZB9qjYtv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJgUk12RkLTZiS43sPKDty2V4sNsABUakC': {
    'private_key': 'Urtqj16N69AGScQAyssjqcz7ZMoLCL6VVoJtXKA1Mz5DQwaTuvDJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSWP83BbWWNfmAcjxrMV149w9E834cTHcN': {
    'private_key': 'UukZ4ZHQeQ65oiD2jucxMquAqCp5xXNDrjHUm9ieFHAd56DqZYZJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDgiGKEZ6qEyFMZKe5jfehwQ361rbaXbDr': {
    'private_key': 'UvrXwpyKZE39pdcdR2Tvjc4y4Sk93FZwPuNFSaL5mtTDaZjF5daa',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNkiRsfar5r2LJ8CzJ2W6donxJFiDp3Wn8': {
    'private_key': 'UqKqXthJXyyHNkiVV2zT7ByKsTbRqH4vyxXFT4TzyYYUhp4RirAr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWgajuPZQHg31KL8x5GHi8hxn9MSXjgKk1': {
    'private_key': 'UqJvoTUo9dQaxN3kZ11UcwfdN8PNPePKFxARW1GnAZYvaHyegZBh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPZrhrzYPeUGsBqk2dB32XC2SVf53jXsvG': {
    'private_key': 'UwGKGTvRaqpKip6gEX1yvCBjb799CzAFX2DUfHGe7D7eF5vLNMzH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNTNBAQ6YTtWPLgJmescAhKLgzqgDLDjbM': {
    'private_key': 'UxXhENSxofmGEowVBhmFMnmMP2AVjDNQA4T7Kz8bVHPMK85jcrHb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXvdrdpBYCWaQf36s8gpVLVgDptfSkNdJn': {
    'private_key': 'UxHz173FXvkkgPmEBaDizG5bxFrg4hns7NTB7RHP1xNyTH3NgtaZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJHg1RNgrP3rAU4fTARZbtkjrbtppLcVm3': {
    'private_key': 'UsSyt3GxuW5UyH51d5igUWLo8AWcGm9UEActS3zbpBv1XMNxpDRd',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RA7xgJWap7HPNG2qKtntLP65AgvQj58WiQ': {
    'private_key': 'UpQAq9QKDYDu3FcAkNEgwPe994MobdhK6ZaFGoqBFy2wFNZpawTy',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKWwC59detBvYNXLL9e88tYywgwUAfh68a': {
    'private_key': 'Uvv9ZoEjayCyBHVXedkwD4dbdnPhCQMzFW1RUHuMqFFGF59UnbS6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVtn9JAqcQgeoiG9VyUbh9PxGe4QR1Vv1i': {
    'private_key': 'UsfUPVm1USbzms2eL6btj8h51a5A6dNYHpkzqgQFAU8Bu9FmixY9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCxQcGebui62AJ5hMgnjUb3Ue7csAW35ht': {
    'private_key': 'Uw59pKXETaBhHc564DxhZLVh4EKSnCPkS89JEUdGyiXzhsFV5CbN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMZARbAs3P3i1RhTUEqTZf8eHHKdA2ger3': {
    'private_key': 'UxMNypUJjgPLRq8Zt3QJgKHpeTb7rnijw3M1SxzYNR6tRcxuXWq2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFxso2QKsLiUQmpP5SYzJwCUVznoGpWCYG': {
    'private_key': 'UqPxLsAfQK99yqZ49mVcLoUG5mchfYgUVVfEen7z9EKEa3ByDYS2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REdkhF7mtcgyC3iZz5dyKYbwuTGifs1vYT': {
    'private_key': 'UtGSLApNcAiHmqTrDk7Dpb2rLkMSR32dqV9xJFBZ7SQks7k3gH4V',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLS384FLfpPrQWYm9xvQ65u7W3dz8QrT1h': {
    'private_key': 'UpWmw3EvPh83TkHtZA4czWCUvpmk7FrNsT3tmXMHoYETNkLASn2N',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPZHKbkkmi2JhCy7zsKXn3vKb144hqcgJ5': {
    'private_key': 'UvWCADdfuyUEwz4hM6N8yUXEPNDthNvDJfDMdohteZ1xXDjmvb7v',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RPg34hiFaPYjZ7Cr53F2aqLWE8pEt7yJgJ': {
    'private_key': 'UuNdLZo4pGyJt2rdESVWGoZxJyQYxbadgu8YCS8Jr6YPeAmV3zaA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQh8GjoVqG6bp9GGq3wss7oaeqkFzzuMiC': {
    'private_key': 'UwPNJu6MWH3oqwHYFRVMTAWWsfyw2ADAKbUAtzB3kB9A9YTvLZBm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFGbTJyGmv3vcMd9QkRZEebHRqtiH4dEHK': {
    'private_key': 'Utr4E8gaGYeUFtmeQ8tGbzaogyUgY9Zhf1bA5Sr3HA8s6WvMhVpr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RM5rvunSto3TW5uhQgNhLPHPuonWoiai38': {
    'private_key': 'UpDSSSoBPW1boA7UeD56QDe8MDeVioNaXviEEb2eiicNYvHyU3MX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKJEFCD8B9D8nfaz21HKxMYEEQYxAHNUgH': {
    'private_key': 'UwDkDAg9whW4phhy1JSqbDpptGx2bgaVcaST6CuCcaFhwENnteHF',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RTLBBrao8ctfDuNvcVe9DwqVHb3U8vcfDH': {
    'private_key': 'UuU5Zy6gaEqqy1bVZStmt7pfuShose8tdWJipBp28AS74eKH6NPf',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYQ5FKrKbAqoKSWETsa2Y1VjGZ9ttEteDV': {
    'private_key': 'UtAgmoxRHfHipy7BaStTQ7tG5Gg13igjwAu9n7K6TzaAhzUwYzV5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMnyTchDCLBioB3whSB23LYa7ZJXa2Mpbe': {
    'private_key': 'UuvZA6a4yHGpUvdCZ5maXYHqA9LoXGDAjymwyqxa1GXUoBmyoM37',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWRr1d7bixgRsk67MD9Bgvb6eh12AaZyjZ': {
    'private_key': 'UvsuRiPgZ8yiVyNNmmozPZYYaYQr1brg2Ly1FborTENRVZQ9LRXb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXEqNdD2qX36E9Knv9dEa93WHjm25da8nc': {
    'private_key': 'UqubMw4YHRfWEhxZu9pb9fGN2pPV8tVu8FGwAQBCom34LYAfEDo5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBS8Xm1asm4kA6P2zsibxdunweHqLrsPj1': {
    'private_key': 'UqzcqtnhupYcvE66vtbS4fQkUWc6APjNhd6Wet5ECzD9AwdGDuhY',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAbd77RxDNafRBnWxqie2KEQvDizHighHR': {
    'private_key': 'Uw786oACNtktYSL4jLWzfeU9m4Mrg4MxdvbisJCnXibU8oTjZwJr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCXL8DF6tcfEUFtjD5D2XftnMP4VD2PSmL': {
    'private_key': 'UvXH5y8k7xjixmdq9v4egmLoXdY5jwGoPPcmXFz9tfbTdukwuZfk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDSqqqkAmjy4YmcFN5rRxw9c59XqYfQi9R': {
    'private_key': 'Up1Zxodv1PdRayGaK1PX5V87MkYBN1zmRJm5usGpnAanuhCXt4vS',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNwC5NrVogrwqwDTrLGpL8PPSPDEiAvQdE': {
    'private_key': 'UsJz4FR4wR3DDeHwyZccJMv7qTADR8AEcrc62w3Vk14m4a445NTp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REt6SiJ9in9zHk4LWGtA8oJ3aVVFam98TB': {
    'private_key': 'UujqSgJsRktwWxHCtxcHDVYSRxkDWpfdaL72u1GTkHrifWa74ieJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFYpV1xpSJ3Fy24U3E1fbxK21k1yxQPStr': {
    'private_key': 'UsCaLm9yP7H119yeNxF4etc6wYSLoJUcmSsUDHkPMbDHqwCDveDX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGgi2Pz4GspvK5QActRVDmXwWU4K2VJhqn': {
    'private_key': 'UxQGiYfM17Zj5WzweC1NisAVXJ6pxa2U5EzVATyQ2EU4amw6ZJP2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RULTpG7sXBLZU61JXgKbAM5Y8Q6YU2do8q': {
    'private_key': 'UtjD3A9TowVKFee1LTKi3qjkHrW44ZQ459n6rtuZi5NHuRM66d6t',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'R9ZRCMqU4qv1suwgWHR9SnS5Gq4PcamiPo': {
    'private_key': 'UtweBtRZAxkDbEnpdddZAY1uhGHcYZ2Hg1DknhW4D9u6WT32L2rM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVMP76bdR5L28kxBBJJ68QgntqvnKpqSCX': {
    'private_key': 'UskD6eSvNLKRWtBYmG94hukFsCwTtaZ1bNSzcYGJf7KSZKhb8im2',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAHZbF9zr3mrxhNFekzUPhnvaQXoy1ssC3': {
    'private_key': 'UuCiaKBf1W37c1RPhrAsDZgm8v2yy6NJamX4zMhjQNhs3MDdnxdM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMozrZdWudHLbHZwpjcZ5aTZKkxLCLSva4': {
    'private_key': 'UpNdRxuk6XxPPCkjsxYYTVPvqXzsXSiPesrFjyyXqFCdVR2PsBUR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJNEWo3i4BYVfPJ96ZMkAMEP4iRr1o27Gb': {
    'private_key': 'UsMvXa8RKNbWTzvNR9Nm14a45Gm9nzjAr8hYzgJEcuP6v8Z1ekP4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RR7TLS3i3ThQ8upv1ZxaUpN2qmVvt2T7Gq': {
    'private_key': 'Usem9mHXYD4vEeCmAQ4xToZy3sNjyvC26GeryckEispNaiAdM476',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNTkZ3yFZeXsEM26PxvGb35nun1JSi1JBV': {
    'private_key': 'UuxGN58U9ov2DppUyzws64RKSoPia34EB6cMhy34nsmbnFcT4Lfp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDydLD3RTP5m6Wp6LrYTFMaEdogX37DPVK': {
    'private_key': 'UvoJEKEQXiYcajoxASgtf7v2BTiNYsjJxdLoC3qCjWEBVgnpBMcF',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUv7ZaPFtruAtZRK5aYitEGwpCx3SHGxfp': {
    'private_key': 'UtqK7xbha7TFzYCkRYcRh4V2zWsbjs3oqrJgPjnCXnJmXi2Lh198',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RG3fJP5N8Ws5rHevM1pJzL3dH7iyMeHmtt': {
    'private_key': 'UwAEoa5gRv9GKTFk263HW7cs33ijVHBLC8tYfXvhzWDdhrCqCXQZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RMLkar7jefc9Jize7JZNLMTCduNbAd8Gpn': {
    'private_key': 'Ur7uyCu6jvyEPUykkzY9Xus4md4uJTsHGnhGVwisRx2Q9KXbLZiC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RAiaRnit6pJUbt9KF4KrFj7FUvFsEeW6TG': {
    'private_key': 'UsuULbr4FmoF3BkuKrUQabS2QHS4VeRYuUbwKiZRuZaubXGWknD4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJUfv2DFUUBS4TEd7MrWH7H4mvPwBkXT9g': {
    'private_key': 'UrHBR2HSZejqyxdErE2XkdTEkxa5rfGtg6jrc28BmLR2iGq8j259',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUn5SPJWrQ1z5tPUSHoRXDoiekKphNKMCV': {
    'private_key': 'UsChGiZj2szQsz3rfSzYss4nHF4u63frArkGyVuqWsfxhdhwZTJ8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQzTM1WCwFvA5tMaZ6kQzwimiRLCp9SBh3': {
    'private_key': 'Usi9CgXWFbAuQYYMxgtPw9mQ5q9eurUFDaWZoR1q88FJjB2pqSNX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL3yVXZcwHru4afbCcThqjEdByQx18EtD1': {
    'private_key': 'UqKbabzGV6DyDTsqLS81kndyfEAVhYpn1CL2SZpoojGYgtwRfprL',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX9LWeXyqxbt6DWqwSdFuxdt51REj9x7Hg': {
    'private_key': 'UpGhuvQFgMeL1KxV58JHCNQwqn5vPdV9FxFyWG64HXTnSU9oBxpm',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RRS9wZpSRCJTJgAP1UUb5BHmQAR36RokCa': {
    'private_key': 'UrAhvvCtQjfwMU9skqPhVUKsGaW7BgVV9Fm47TxBW6rVbzMQp8Bk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJWjLZMJJyEEreUuQtbCySxLUS871mpdAz': {
    'private_key': 'UvCGBmqNuQLi6VG4Nnq8xoWraAzm2yh81DsXZuMpwYeb9w6hrp5i',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSfu5E6B75VyYnK1ftBfN5JPWijfoCzgpQ': {
    'private_key': 'UvxgVXT3fuUmDEhe9cTf2ejnT6hYEngrnWQhUULE7smbzNxuLCFR',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX7pUVmbyVcCXnAPQCkqTsyU7VLuxuRPuQ': {
    'private_key': 'UxHATt65WkH7urMPFu46huG5DDjhiUurY4ZutGMD3yvThkbEjXDh',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RYW2AHjJRj5GTMsYYy3BUV3jgtcZLy1VN3': {
    'private_key': 'Ut88PbKCqv5zymn91S4nFEJuJ97q3D9FZXPuLddBA7jw1TNhwCmk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUeCRUWsKqHeyPLMdKEutwYHmCeMe7Z2u3': {
    'private_key': 'UtREbnKCKGAMW8MzDWmv4eh7U5Ue77cNoNhwgSLGpKkvjNecVBR8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKLhcHtGjgVsqoQH7yoiRTnxzTqiw2hqAz': {
    'private_key': 'UvxXnvJkX43dkQYJB53vAFum9T3WiCiX1BwatTdG4afVF6YJgJF1',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REwATRrvgxVYhupzbm3EHTzrJ9iaDTbE4e': {
    'private_key': 'UwLdN3q8rpX75HMEs7nbCquqRBKwcKkWb3GHaewZWyZL8dtbH6c9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHiuxfVvCJw3WkC8QhcMJyaz8R3H6bDvrT': {
    'private_key': 'Usmtdc9BAX6JWje8X1tdMubRDGJMHv3tgQPkkrtjuccFRoajizmk',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWGdCfrxXPcZn5acvfH6aheWkBzizAchze': {
    'private_key': 'UtP2HgnCq8XfLMct55zPN4qrYzn5ALEazxPTqRHW114hqdS18on4',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RG8pRqR2h7aYJbLVL2TMQXa3kWa4acVRnb': {
    'private_key': 'UvpZ3Pc5GHPRNSUXcPPHu6cZ3G9qPm6D59aXi9knN1cyMqjjqL9k',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCKdLhkqDX7FWuqtncgSUjHFc4KutHSCk7': {
    'private_key': 'Ut7ACkQNeeoi4vtdDw4ZjWGwX53KcBUJ8LuVx5sSvVxxqQhzUTdM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RT2D2WY5kGetdTKXvS4V5d1S6X5WmWhf3B': {
    'private_key': 'UsQj6QFPnB2u9tad3jLGrxB5bzerZVQPwgN8cinuL7qvu1VA3jRN',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGzUR9zsiXLGg5teRcFovVSYq4Jm6RTLdQ': {
    'private_key': 'UsJmRR9LN5D3WJJHGLMG9dYfBhqEjc5x98stmCq2Pr7VbwKfVarv',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RBe57PjiYx1zcVzXQGRMCVWnVqqNER6o8b': {
    'private_key': 'UwqqKwtnyHwm25ZUvWqva8mbpjonczmz8a8gwnfnpu7eQLbe7vBc',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RJAV3gDm3LyqwDCPRr285at15JPEQ6Erq1': {
    'private_key': 'Uq27DebHcmRHpQafFTSGhY9U973fHQRhGQKRJ3cdphKc2X2UmBzV',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RFxp1aaaNjm8srJn6kjxE64thyqTQ9q4um': {
    'private_key': 'Ur19mZFLpDmxUYdQdhy2AL6gQEjWmqu1FhWLGkvXcCGBL2iHFAMM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDgZnvGpWFtG1vUCbP87Wt1VTPF3nfmB3t': {
    'private_key': 'UueznYXoN3VBK6gNYTYiWe9zuGZNXjW4FyPQncVx4DLH7FMe6An7',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RX7hWWSNPw1rRrK5XF4VpsnZCyMt7taff3': {
    'private_key': 'UtogFbsDpiBy2c38zYwgyv6xk6KPSPC79mMbPEvuDfTRUAxbnKWH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REiPyGKcZ7xWo3cL9kGM6EUkHZ8o4Ysn4w': {
    'private_key': 'Uuk6eriYrb6tpNxLxCjaRdzry6wKUikysVCbL7HDy2fkNvx6P4GA',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RV1NWzWHNzQ4rhNUdtXW6wmo5UxHq8Qqzb': {
    'private_key': 'UvYt8paPnAXuH4uUAnEAsu966QDomLXnorhFGokDhepczA5bbHLp',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REThVeXoEfyfU8a988FGccxVRswzzfHX13': {
    'private_key': 'UrHYX3aXN56chCPC6JmyBgeg5YxMByiNNn3FGX8Cd7dViiHhfEsP',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGoETmF7PAcCU4qe54hYxZxhezrSFDTenE': {
    'private_key': 'UqYPCu8snp4cLbyrAWwzZj2BSSja5ueFmA69dsgn2BXp9iNJz58W',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKzk42LVW6p9wz7vdamRgZfohKJqKjY8dU': {
    'private_key': 'Uw2sTCBnA1zvHKpumAFJVSaEgspYYv2rS9pp5o74rushbJS1fwJ6',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKbLbZLEL2PXrqUXgU3yGAUBgRnxMHYDYQ': {
    'private_key': 'UsZC835JC9tjD9n89MWfre1P7yKRbyrpkDuAQe7soEe43ocD6ZGH',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNuKrQf6TSL5nof2NRs5VhAbyZtAs9qVrk': {
    'private_key': 'UtYDYPbNrQiVpqr6aKq66RBSaZQrDXEvcc88QpjrGZWwwwjPnmRX',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RQJHZjcGviQxaJxxvQsywesUqMYk4jgKGY': {
    'private_key': 'UqPZVYHR6ASg54ynL1QUmHsqd4EZ1abzwMTCHo7jq58FGtAFETdC',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RT8vihmqz6AU6cdWNtqiF15edapcEeypie': {
    'private_key': 'UtTTnsd7b9crHa825sc7Tjn8zjMR5YFJqqCHfHruAZWkjBUjBWEM',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RP4FJFz4X4Utpphqddew4SCaTa2DoLsyuW': {
    'private_key': 'UrK4kKw1CwbAY5yckN6Yy7YrXd89e8e31szvKKLvAWsVwGp839My',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKHHme1crs4Wd3KHCjfCVfHPwCAnjgND3k': {
    'private_key': 'Us4VrBFpB17bs8YURvRfdusBSbNYr3aEoctjkmXjx8cUqNvpJdvb',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RECjyaXbRueGHbXLCyrcs6pfwmJ7zqSxeh': {
    'private_key': 'UwFyBb21BiYLz5QuMHtaF54sJyh1SSTBoUSRDBFFhLnD2GLxDXo8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNnHFBVHAXbsWoJqZbx95CHBi2JiaHBeq6': {
    'private_key': 'UwskLnsFTu82jq3UMxbWXSp24YzLMjwuGo22ikQrKuSXYhUyjrqq',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RES33w8KADMJnAuuA9zQLQyyLb6Bg3hk6i': {
    'private_key': 'UtF9cQSGXVazS5MC7FSzo89MX3BhZL2qasF8VsHTtPBcL8u9Byqo',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUiC86Lpgoi2u9QgDczXUYKh7guuuppNqG': {
    'private_key': 'UuemhNXpQkhi8yCHCUvNA6DcJAGsNyuj6fE9qPSwcFVwUoXskJ9M',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHRQNZW8HLcvdngs3hm9o4onSKBiMJ9RhT': {
    'private_key': 'UvmNMbUEeEbA3REqZBpGrcZorvwfgnUNheGpwAxL4cfJao4RRyhG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RL29oXDVVyQkcGdFHqzWQ5Wzy6Xha92P4b': {
    'private_key': 'UpxEEpT8SdDocdkjCU1TCAmimESFjDiqNnkL3JnTyXsFvuDfQQoe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUXBad3dA5G452N7C8pqxTFfYsU2Q8qCfQ': {
    'private_key': 'UpjGQupHxZs4uNDhVaBNFuzi3FXnS9Yb2dkfnrJLpkstYZsWTZmZ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKBB4y6sr3yHRnNCoYqtapGg3QkqdkBxxh': {
    'private_key': 'UtTEnDHS4EMGEWKewMcfEckbyC3Fg1UptEHax58WjrKNBARBcxT5',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RR7SGmCH6n8hFNbLMmkSfiGQsh8UB17AXe': {
    'private_key': 'Us6Y5jBkAgk2eSWsdmGBsFoL1r4w8JB6uHR4xrNcX79cVhVQeMDe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNoBHxwjx5M6bRt1riMBwig82XEQyVXHLN': {
    'private_key': 'Uw67cuUJDF87b5kbrJVK33ZQMjx35M4SBerYstCYh6hqaXAfb5oG',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RXo7Q88iSrmXq1zVCPqczR2sEUqxu34aNU': {
    'private_key': 'UrBKt2cxLNcJWwEtipw7bDS6pvFjzCk7axqh7wrQ92tSEsKyyRWJ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RKJAgvuMprfXLKhTppxirU7w7kuEmdsR6q': {
    'private_key': 'Up8Knr9FKRF8rR3yAcK1cBBYNwzAhLPWcdKx8MwqE67drTMwAHE8',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RSX1gDWPmWw7Rws47pSuQXFfAibAXZ4RcD': {
    'private_key': 'UqGs3VzCocFzWdfktcYxZPFUAkur986LPMQyaSd7REG2fD6bipT7',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RGccKWsSgECvCEf5fQn3ZHdUq6oHgFLSHq': {
    'private_key': 'UsnwDhonaworxMiKAm3Q2LXKQzhUgDtiarg89TMZxMgFpvAXeR8f',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RNZL5vmoZWkziwyWkkBxQDUaYwu6a4eDUX': {
    'private_key': 'Us9H7hgbFFyJFwjesdadXDVhng5Uf5ihZ6NDieX4YLbjHy3WP9YD',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHpoPmXUMnZ4snTtHQoNmLfwAf4BbbjMyg': {
    'private_key': 'UuYhCvgYgd96Z7fmjFye2nyMz5nasuvoBsFStzEZYgP3EPRfLhwr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVRVev8VdxLvJ7R7Bg43E5Mk4YLmuqTjLY': {
    'private_key': 'UuDXjDT8uU5NhRkteTSEkBDAEfLthXAJ3dv9TidHrEG31w1wgDSj',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDoHwtx14PW8rUdJMgoH4RUSoSZpRRvqV9': {
    'private_key': 'UsC1HJ5oeywtJoUfrW5pCHqhs3zNePZRG9GAR24LT1E4vAgZdpmQ',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RWQZeYUkpAsTxvUqXXQ2XLi1mKo44ENqLm': {
    'private_key': 'UrDQ4n9ug8Emx2VEMkPbXKLwqnwuWkqJvJJEFWESioSvpS1oabcy',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RCreATuAUnVGgrajtamcCVkz1f7TUZ42NT': {
    'private_key': 'UrkASMqCNsi2CPezgRDAMiSnxCK4qAGWd9ci4s4caTgnh5EirqLF',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RLBXz3NcSphG2uvGEsMHkPDNE9w5G64xf3': {
    'private_key': 'UvAjyN6V4AkKxpfxQhtrsTUzePzbjNWYeVKLZwz3J8fjeh6jcDpe',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RVoysqQre1A6bmJst1kbVDeTgracCGYGgo': {
    'private_key': 'Uq8bWb2Sn9gwwwqUCPVgTVJsJAcRhSPkhCnaBA1a9hMGmesmZVZt',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RF26XBT2xWD49Qh1ySbg8nu9Z1rQ7GySCL': {
    'private_key': 'UpTxAys1YMYvjmd64TNsXgrAfm2QuFW8YUhrCn2ADCeq6Z2Wygkw',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'REoVKVD84dhbiNnBm44jsFVPthRgRoTJgd': {
    'private_key': 'Uv8vibPKcrqxwqRgdGCLrs4M5mJqxQNNMtpZ7NcowRj6xALMpeJr',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RUGWKBozdTNJBnkyWZVnZksfLMrThat2P1': {
    'private_key': 'UpaoZFaV1N5HhBaJmLge6eHsQPNEK749VW6s2DJ2RgcMbDhrQ1bd',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RDvCrWVTRMdGhF9WeDSKCKaNJz3y3Ec5mn': {
    'private_key': 'UpGMk97MW7zu8E89UBybwswGwrtP6LxBnFp4mtm4ubftfP4vAeP9',
    'is_funded_rick': true,
    'is_funded_morty': true
  },
  'RHbbaaxhWSEtesWDs8bRiVvsveU3g7AYHx': {
    'private_key': 'Ur5W4FWXJ6uK7giFFJpXtwuaPF8cgQJZk1GjvfABCAi2JKbGnQZ6',
    'is_funded_rick': true,
    'is_funded_morty': true
  }
};
