# Validation — Dart 0.7.0 / JS 0.7.0

15 octobre 2026, macOS arm64, Dart 3.14.0-211.1.beta, Node 22.12.0.

- Analyse Dart du SDK et de Snake : aucun diagnostic.
- SDK : 41 tests hors réseau passent. Cela comprend quatre scénarios de requêtes
  comparés aux fixtures générées avec le package JS 0.7.0 exact, et trois tests
  sur serveur HTTP local pour annulation, timeout mid-body et annulation du backoff.
- Snake : 15 tests passent, dont le rendu et les contrôles Nocterm.
- Web : compilation dart2js, puis exécution du résultat sous Node avec
  `self=globalThis`. Assets base64, Box, usage nullable et zstd passent avec un
  transport simulé. Cela ne qualifie pas le transport d'un navigateur réel.
- Runtime VM : scénario local exécuté et reloadSources réussi sur une instance
  lancée dans ce dépôt. Aucune autre application n'a été rechargée.
- Qualification API : huit scénarios passent, sans fallback, quatre avec le
  client HTTP/2 par défaut et quatre avec HTTP/1 injecté. Voir
  [le rapport mesuré](../compatibility/api-qualification.json). Texte :
  jev-1.13.0 ; images/Box : jev-1.14.0. La qualification a précédé le renommage
  de version 0.3.0 -> 0.7.0 ; le rapport conserve cette distinction.
- Veille : interrogation de toutes les releases depuis la référence auditée,
  du commit du tag et des quatre contrats documentaires : aucun changement.
- Cohérence manifeste/version/matrice et `git diff --check` : passent.

Le benchmark JIT `tool/benchmark_compression.dart` mesure uniquement trois
charges synthétiques très répétitives, sur 100 encodages après 20 warmups :

| Bytes JSON | Bytes zstd | Temps moyen µs |
| --- | --- | --- |
| 2060 | 46 | 432 |
| 32780 | 46 | 837 |
| 65548 | 46 | 798 |

Ces mesures ne représentent ni des images réelles, ni un débit API, ni la mémoire
allouée. Le niveau zstd 3 utilise une fenêtre au plus de 2 MiB, sous la limite API
actuelle de 8 MiB. La compression et les corps multipart sont préparés une seule
fois par appel et réutilisés lors des retries.

L'alignement reste partiel : HTTP/2 ne prend pas en charge l'abort du transport,
et l'API Dart expose une réponse bufferisée et parsée plutôt que JS asResponse().
La compression pure Dart sur Web est une divergence volontaire.
La veille GitHub devient active après le push des workflows sur la branche par défaut.
