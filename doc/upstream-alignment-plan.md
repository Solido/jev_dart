# Mise à jour et suivi de compatibilité TypeSafe

Audit du 15 octobre 2026. Plan exécuté dans la version Dart **0.7.0**,
à la demande de conserver la même version que JS. Le manifeste et
COMPATIBILITY.md sont la référence courante ; ce document conserve les lots
initialement prévus. Les qualifications live sont dans
`compatibility/api-qualification.json`.

## Références

- Dart local : `pubspec.yaml` annonce **0.1.5** ; `lib/src/version.dart` annonce
  encore **0.1.4** dans les headers. Corriger cet écart dans le premier lot.
- Cible JS : **v0.7.0**, publiée le 14 octobre 2026, commit
  `b844cd1aca12855a5d24a2df52a1401c86e7d37a`.
- API HTTP : routes `/v1/systemone` et `/v1/models`. Le préfixe `v1` ne prouve
  pas la prise en charge de toutes les fonctionnalités ni une version du modèle.
- Le modèle par défaut `jev-latest` est un alias mobile : enregistrer le modèle
  effectivement retourné lors des qualifications.

Sources : [release 0.7.0](https://github.com/typesafe-ai/typesafe-sdk-js/releases/tag/v0.7.0),
[types JS au tag](https://github.com/typesafe-ai/typesafe-sdk-js/blob/v0.7.0/src/types.ts),
[validation JS](https://github.com/typesafe-ai/typesafe-sdk-js/blob/v0.7.0/src/questions.ts),
[contrat HTTP](https://docs.typesafe.ai/api),
[images](https://docs.typesafe.ai/images),
[Box](https://docs.typesafe.ai/primitives/box).

L'API GitHub des releases a confirmé 0.7.0 alors que la page web consultée
affichait encore 0.6.0. La documentation évolue indépendamment des tags :
conserver ses empreintes et traiter les contradictions comme des points à vérifier.

## Écarts constatés

| Fonction | Dart actuel | Action / preuve attendue |
| --- | --- | --- |
| Noul, Choice, Score ; modèles | Présents | Fixtures communes JS/Dart, puis tests API |
| Score.criteria en liste (0.6.0) | Déjà présent | Vérifier JSON envoyé, score fractionnaire, legend et probabilités |
| Listes de score construites à l'exécution | Déjà acceptées | Conserver ; documenter le rejet anticipé par le builder Dart |
| Usage nullable (0.7.0) | Cast obligatoire vers num | Rendre les deux compteurs nullables ; ne pas transformer null en zéro |
| Validation Choice/Noul (0.7.0) | Seulement ensemble vide et taille minimale Score | Rejeter Choice vide, Noul sans instructions ni description d'issue ; vérifier state non null |
| Erreurs de validation via Future (0.7.0) | systemOne est déjà async | Vérifier la propagation et l'absence d'appel réseau sur requête invalide |
| Images/assets (0.7.0) | Pas de modèle d'asset ni paramètre assets dans systemOne | Ajouter API typée, collecte récursive et sérialisation |
| Textes avec assets (0.7.0) | Absent | Équivalent Dart de withAssets et join |
| Box (0.7.0) | Absent de Question et Answer | Builder, coordonnées, réponse et confidence nullable |
| Compression zstd (0.7.0) | JSON non compressé | Option désactivable, seuil 1 KiB, support selon runtime |
| Métadonnées HTTP (antérieures à 0.7) | Succès sans response/requestId exposés | API additive avec résultat, status, headers et requestId |
| Overrides partiels retry (antérieurs à 0.7) | Remplacement de la politique ; copyWith manuel | Héritage explicite des champs non fournis |
| Annulation transport | Arrête l'attente ; requête envoyée peut continuer | Pré-annulation sans envoi, arrêt des retries ; étudier abort réel par transport |
| Changements Node.js / exports TS | Spécifiques à JS | Classer non applicables ; préserver pure Dart et Web |

La présence d'une fonction ne vaut pas certification de parité. Les tests locaux
actuels ne sont pas une comparaison différentielle contre JS 0.7.0.

## Lots de mise à jour

### 1. Correctifs de contrat et base de suivi — cible Dart 0.2.0

- Synchroniser la version des headers avec pubspec et ajouter un contrôle CI.
- Supporter Usage nullable, renforcer validation et figer les fixtures des
  réponses/requêtes Noul, Choice, Score et modèles.
- Tester les erreurs de validation via Future, sans requête HTTP envoyée.
- Reprendre les scénarios pertinents des tests JS du tag : erreurs HTTP,
  Retry-After, headers protégés sans doublons de casse, corps interrompu,
  pré-annulation, timeout et attente entre retries.
- Documenter la migration des utilisateurs de Usage : les opérations sur les
  compteurs doivent traiter null. Le passage 0.1.x -> 0.2.0 signale cette rupture.

Acceptation : analyse Dart, tests hors réseau, tests de contrat différentiels,
compilation Web et preuve de version cohérente. Statut JS : partiel 0.7.0.

### 2. Images et Box — cible Dart 0.3.0

- Ajouter Image depuis bytes/base64, assets nommés et textes avec assets.
  Prévoir fichiers via adaptateur IO, sans import dart:io dans l'API commune.
- Collecter les images dans state, instructions et critères ; générer des
  références, dédupliquer et contrôler les références inutilisées/collisions.
- Implémenter JSON base64 et multipart avec fixtures comparées au SDK JS ;
  garder les données encodées réutilisables entre retries.
- Ajouter BoxQuestion, BoxAnswer, BoxCoordinates et accès typé au résultat.
- Conserver l'activation expérimentale explicite avec
  `TypeSafe-Danger-Zone-Images: true`. La release recommande `jev-preview` ;
  les docs courantes mentionnent Jev 1.14. Vérifier le modèle disponible avant
  qualification, sans changer silencieusement le modèle par défaut.
- Tester PNG/JPEG, nested assets, legend avec références, coordonnées et
  confidence null. Vérifier les limites à partir du contrat figé.

Acceptation : tests locaux + Web ; puis qualification API distincte sur image
connue et questions mixtes. Vérifier schéma et invariants, sans exiger un score
probabiliste identique entre deux appels. Garder le statut expérimental upstream.

### 3. Compression et ergonomie de transport — cible Dart 0.3.x

- Évaluer zstd compatible VM/Web, coût mémoire et taille de dépendance.
  Activer seulement sur runtime pris en charge ; fallback non compressé et
  `compression: false`. Ne pas imposer une dépendance native à tous les clients.
- Vérifier le seuil 1 KiB, Content-Encoding, taille décompressée et réutilisation
  des bytes sur retries ; mesurer le bénéfice avec le benchmark existant.
- Ajouter métadonnées HTTP et overrides partiels retry sans casser les appels
  Future existants. Définir clairement la propriété des corps et le parse unique.
- Qualifier l'annulation sur HTTP/2 et transport injecté, y compris mid-body.
  Si l'abort réel reste absent, le déclarer comme divergence maintenue.

Acceptation : fixtures de compression, serveur HTTP local, mesures et tests
transport ; preuve API séparée. Ne déclarer la parité complète qu'après revue
de toutes les lignes et des divergences acceptées.

## Suivi durable à implémenter dans le premier lot

Créer `compatibility/upstream.json` comme source de vérité, et une matrice lisible
`COMPATIBILITY.md` générée depuis ce fichier. Champs proposés :

```json
{
  "dart_version": "0.1.5",
  "upstream": {
    "repository": "typesafe-ai/typesafe-sdk-js",
    "target_tag": "v0.7.0",
    "target_commit": "b844cd1aca12855a5d24a2df52a1401c86e7d37a",
    "last_reviewed_tag": "v0.7.0",
    "fully_aligned_tag": null,
    "reviewed_at": "2026-10-15"
  },
  "api": {
    "route_version": "v1",
    "documented_revision": null,
    "contract_snapshot_sha256": null,
    "last_live_verified_at": null,
    "verified_model": null
  },
  "overall_status": "partial",
  "features": []
}
```

Chaque feature porte : identifiant, source (tag/commit ou page API), statut
`aligned`, `partial`, `missing`, `intentional_divergence` ou `not_applicable`,
tests/fixtures associés, dernière preuve et éventuelle tâche de correction.
Les champs null sont des informations non établies, pas une compatibilité implicite.

Conserver un snapshot daté des contrats API pertinents et les fixtures JSON
canoniques. Un même serveur de test enregistre ce qu'envoient les deux SDKs et
leur retourne les mêmes réponses. Comparer JSON après normalisation, pas les
UUID ou frontières multipart aléatoires. Épingler JS au commit audité.

### Contrôles CI

1. À chaque PR : version pubspec/header/manifeste cohérente, matrice générée à
   jour, fixtures et tests de contrat. Une feature ne passe à aligned qu'avec preuve.
2. Chaque semaine et sur déclenchement manuel : interroger l'API GitHub des
   releases, paginer pour ne rien manquer, filtrer drafts/prereleases, comparer
   toutes les releases depuis last_reviewed_tag et leurs commits. Vérifier
   séparément les empreintes des pages API/images/Box/modèles.
3. En cas de changement : proposer une issue unique « alignement TypeSafe » avec
   différences, breaking changes et checklist ; mettre à jour cette issue tant
   qu'elle reste ouverte. Une erreur réseau est une erreur de veille, jamais
   une confirmation d'alignement. Un diff de docs est un signal à trier.
4. Avant publication : revue de la matrice + tests API explicitement lancés avec
   secrets protégés. Enregistrer date, modèle retourné, transport et périmètre.
   Ne pas appeler l'API payante à chaque PR ni transmettre les secrets aux forks.

Décision finale : la version Dart suit le numéro de la cible JS. Chaque release Dart indique
« référence JS auditée », « fonctionnalités alignées », « divergences restantes »
et « dernière qualification API ». La matrice explicite le périmètre malgré la numérotation commune ; `v1` et `jev-latest` ne sont pas des numéros de SDK.

La veille CI et les fichiers de suivi sont implémentés. La veille démarrera
après le push du workflow sur la branche par défaut. Aucun monitor récurrent n'a été activé
dans l'application Codex pendant cette planification.
