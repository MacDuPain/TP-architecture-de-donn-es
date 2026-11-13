## Phase 0

Face à une utilisation grandissante de l'application, les ingénieurs Discord ont dû corriger l'architecture de la base de données pour pallier plusieurs ralentissements :
- Lecture des "Tombstones" trop longue (valeurs "Null" + messages supprimés dans les salons)
- Saturation des nœuds, augmentant le délai de réponse des requêtes
- Redémarrage manuel de certains nœuds

Pour pallier cela, les ingénieurs de Discord ont procédé à plusieurs modifications :
- Coalescence des requêtes
- Écriture des valeurs non nulles uniquement pour réduire le nombre de "Tombstones" par message
- Découpage des messages en partitions de 100 Mo

**Chiffres structurants pour la conception :**
- 100 millions de messages (sature la RAM)
- 100 Mo par partition
- De 177 nœuds Cassandra à 72 nœuds ScyllaDB (de 4 To à 9 To par nœud)

## Glossaire

- Ami : Utilisateur avec lequel des messages directs peuvent être échangés.
- Membre : Utilisateur enregistré dans un ou plusieurs serveurs Discord.
- Modérateur : Utilisateur avec un rôle de modérateur
- Propriétaire : Utilisateur auquel le serveur appartient.
- Présence : état de l'utilisateur sur l'application
- Salon : Canal de communication vocal ou textuel. Seuls les salons textuels peuvent recevoir des messages.
- Serveur : Agrégat de canaux de communication

---

## Phase 1

### 1.a

| Objet métier | Qui le crée                                        | Qui le supprime                            | Remarques                                                                        |
| ------------ | -------------------------------------------------- | ------------------------------------------ | -------------------------------------------------------------------------------- |
| Serveur      | Un utilisateur, qui en devient le propriétaire     | Le propriétaire                            | Que devient le serveur si le propriétaire supprime son compte ?                  |
| Utilisateur  | Une personne en s'inscrivant                       | Une personne en supprimant son compte      |                                                                                  |
| Membre       | Un utilisateur en rejoignant un serveur            | Un modérateur (supposé)                    |                                                                                  |
| Salon        | Un modérateur ou le propriétaire (supposé)         | Un modérateur ou le propriétaire (supposé) |                                                                                  |
| Message      | Un utilisateur, qui en devient l'auteur            | Un utilisateur ou un modérateur            | Date d'envoi et date de modification                                             |
| Pièce jointe | Un utilisateur lors de la rédaction de son message | Un utilisateur                             | PJ supprimée avec le message => Attribut du message ?                            |
| Amitié       | Un utilisateur en envoyant la demande              | Un utilisateur de l'amitié                 | Où sont stockées les demandes en attente ?                                       |
| Présence     | Le logiciel                                        | Le logiciel                                | Renouvelée à chaque nouveau signe de vie et supprimée après 5 minutes sans signe |

### 1.b

| Garantie par le modèle (clé, FK, unicité, CHECK)               | Garantie seulement par du code ou un trigger                           | Hors modèle relationnel (autre paradigme probable)     |
| -------------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------ |
| Un utilisateur a un email unique.                              | Pour écrire un message, l'auteur doit être membre du serveur du salon. | Une présence expire après 5 minutes sans signe de vie. |
| Un salon a un nom unique dans son serveur.                     | Un serveur a un seul propriétaire.                                     | Suggestions d'amis et de serveurs                      |
| Une date de modification est après ou égale à la date d'envoi. | Seuls les salons textuels reçoivent des messages                       | Tableau de bord quotidien                              |
| Un membre a un rôle parmi trois valeurs.                       |                                                                        |                                                        |
| Une amitié existe une seule fois par paire d'utilisateurs.     |                                                                        |                                                        |

### 1.c

**Décisions :**
- **Rôle d'un membre :** attribut `role` de l'association EST_MEMBRE (un seul rôle par membre, trois valeurs fixes). Écarté : une entité ROLE, trop lourde pour 3 valeurs fixes.
- **Amitié :** association réflexive ETRE_AMI sur UTILISATEUR (0,N des deux côtés). Pour ne pas la stocker deux fois : on range toujours le plus petit id en premier + une contrainte d'unicité. Écarté : stocker (A,B) et (B,A).
- **Propriétaire :** simple rôle « propriétaire » dans EST_MEMBRE. Écarté : une association en plus entre Serveur et Utilisateur, car si elle dit « Léa » et que le rôle dit « Sam », on ne sait plus qui est le propriétaire.
- **Pièces jointes :** attributs du message (`pj_type`, `pj_url`, `pj_nom`, tous facultatifs). Écarté : une entité PIECE_JOINTE. Leur forme varie (image, fichier, lien), donc certains attributs restent vides selon le type.
- **Messages :** dans le MCD, c'est une entité comme les autres (auteur, salon, contenu, dates) mais avec un stockage différent.

**Entités et attributs :**
- **Utilisateur** : id_utilisateur, pseudo, email
- **Serveur** : id_serveur, nom
- **Salon** : id_salon, nom, type (textuel ou vocal)
- **Message** : id_message, contenu, date_envoi, date_modification (peut être vide), pj_type, pj_url, pj_nom (facultatifs)

**Associations :**

| Association | Entités               | Cardinalités                                                                                    |
| ----------- | --------------------- | ----------------------------------------------------------------------------------------------- |
| Contient    | Serveur - Salon       | Un serveur contient 0,N salons. Un salon appartient à 1,1 serveur.                              |
| Ecrit       | Utilisateur - Message | Un utilisateur écrit 0,N messages. Un message a 1,1 auteur.                                     |
| Dans        | Message - Salon       | Un salon contient 0,N messages. Un message est dans 1,1 salon.                                  |
| Est membre  | Utilisateur - Serveur | Un utilisateur est membre de 0,N serveurs. Un serveur contient 1,N membres. Attribut : `role`.  |
| Etre ami    | Utilisateur - Utilisateur | Un utilisateur a 0,N amis (dans les deux sens).                                             |

### 1.d

**Règles de passage utilisées :**
- Association 1,N : clé étrangère du côté N
- Association N,N : nouvelle table, avec ses attributs
- Association réflexive N,N : nouvelle table avec deux clés étrangères vers la même table

**MLD** (# = clé étrangère)

```
UTILISATEUR (id_utilisateur, pseudo, email)
SERVEUR (id_serveur, nom)
SALON (id_salon, #id_serveur, nom, type)
MESSAGE (id_message, #id_salon, #id_auteur, contenu, date_envoi, date_modification, pj_type, pj_url, pj_nom)
EST_MEMBRE (id_membre, #id_utilisateur, #id_serveur, role)
ETRE_AMI (id_amitie, #id_utilisateur_1, #id_utilisateur_2)
```

**Contraintes physiques (MPD)**

| Table       | Contraintes                                                                                                               |
| ----------- | ------------------------------------------------------------------------------------------------------------------------- |
| UTILISATEUR | `email` UNIQUE NOT NULL ; `pseudo` VARCHAR(32) NOT NULL                                                                   |
| SALON       | `type` CHECK IN ('textuel','vocal') ; UNIQUE (id_serveur, nom)                                                            |
| MESSAGE     | `contenu` NOT NULL ; `date_envoi` NOT NULL ; CHECK (date_modification IS NULL OR date_modification >= date_envoi)       |
| EST_MEMBRE  | `role` CHECK IN ('proprietaire','moderateur','membre') ; UNIQUE (id_utilisateur, id_serveur)                              |
| ETRE_AMI    | CHECK (id_utilisateur_1 < id_utilisateur_2) ; UNIQUE (id_utilisateur_1, id_utilisateur_2)                                 |

**Index et requête servie**

| Index                                  | Requête servie                                         |
| -------------------------------------- | ------------------------------------------------------ |
| MESSAGE (id_salon, id_message DESC)    | Afficher les 50 derniers messages d'un salon           |
| EST_MEMBRE UNIQUE (id_utilisateur, id_serveur) | Vérifier qu'un utilisateur est membre avant d'écrire |
| EST_MEMBRE (id_serveur)                | Lister les membres d'un serveur                        |
| SALON UNIQUE (id_serveur, nom)         | Lister les salons d'un serveur                         |
| ETRE_AMI (id_utilisateur_2)            | Retrouver les amis quand l'utilisateur est en position 2 |

> Les règles « un seul propriétaire » et « seuls les salons textuels reçoivent des messages » ne s'écrivent pas avec ces contraintes : elles restent dans le code (voir 1.b).

### 1.e

**Questions :**

| Question                                                                    | Ce qui change dans le modèle                                                                 |
| --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Que devient un serveur quand son propriétaire supprime son compte ?         | Soit suppression du serveur, soit transfert du rôle à un autre membre (règle à coder).       |
| Que deviennent les messages d'un compte supprimé ?                          | Soit supprimés (`CASCADE`), soit gardés avec un auteur vide (`SET NULL`, donc auteur facultatif). |
| Où sont stockées les demandes d'ami en attente ?                            | Soit une colonne `statut` dans ETRE_AMI, soit une table à part.                              |
| Un membre peut-il cumuler plusieurs rôles ? (ex : propriétaire & modérateur) | Si oui, `role` ne peut plus être un attribut simple : il faut une table de rôles.           |
| Un message peut-il avoir plusieurs pièces jointes ?                         | Si oui, les attributs `pj_*` deviennent une entité PIECE_JOINTE.                             |

---

##  Phase 2

### 2.a Table des accès

**[H]** = hypothèse de ma part (pas dans le dossier). Le reste vient du dossier.

| Accès                                  | L/E | Fréquence                                   | Latence visée      | Forme                 | Cohérence exigée    |
| -------------------------------------- | --- | ------------------------------------------- | ------------------ | --------------------- | ------------------- |
| Envoyer un message                     | E   | ~1 400/s, pic ~4 200/s (voir 2.b)           | rapide [H]         | clé                   | Stricte             |
| Afficher les 50 derniers messages      | L   | ~1 400/s (lecture/écriture = 50/50)         | < 80 ms (p95)      | plage                 | Tolérance au retard |
| Vérifier qu'un utilisateur peut écrire | L   | À chaque message                            | très rapide [H]    | clé                   | Stricte             |
| Afficher qui est en ligne              | L/E | Un signe de vie par minute et par personne [H] | rapide [H]      | clé                   | Éphémère            |
| Suggérer des serveurs / amis           | L   | Rare [H]                                    | ~1 s [H]           | parcours de relations | Tolérance au retard |
| Tableau de bord d'un serveur           | L   | Quelques fois par jour [H]                  | ~1 s [H]           | agrégat               | Tolérance au retard |
| Supprimer un message                   | E   | Rare [H]                                    | rapide [H]         | clé                   | Stricte             |
| Rechercher dans l'historique           | L   | Rare [H]                                    | ~500 ms [H]        | recherche             | Tolérance au retard |

### 2.b Volumétrie

**1. Messages par seconde (décembre 2016)**
- Moyenne : 120 000 000 / 86 400 secondes ≈ **1 400 messages/s**
- Pic (×3, H2) : 1 400 × 3 ≈ **4 200 messages/s**

**2. Volume stocké (H1 : 300 octets par message)**
- Par jour : 120 M × 300 octets = 36 Go
- Par an : 36 Go × 365 ≈ **13 To**

**3. À 100 millions de messages**
- Messages : 100 M × 300 octets = **30 Go**
- Index : 100 M × 40 octets = **4 Go**
- RAM : 16 Go (H4)
- L'index tient en RAM (4 < 16), mais pas les messages (30 > 16).
- Conclusion : les lectures sont « extrêmement aléatoires », donc le message demandé n'est presque jamais en RAM. Il faut aller le chercher sur le disque, ce qui est lent.
- Si un message pesait 100 octets, tout tiendrait (14 Go) : la conclusion dépend donc de H1.

**4. Contrôle de vraisemblance**
- 12 nœuds × 1 To = 12 To
- Avec la réplication ×3, chaque donnée est stockée 3 fois : 12 / 3 = **4 To de données réelles**
- 4 To / 300 octets ≈ **13 milliards de messages**
- C'est cohérent avec « des milliards de messages ».

### 2.c Dénormaliser ou pas ?

| Accès                | Contrainte           | Technique                                            | Coût                           | Garde-fou                                  |
| -------------------- | -------------------- | ---------------------------------------------------- | ------------------------------ | ------------------------------------------ |
| Tableau de bord      | Reporting            | Table de stats calculée chaque nuit                  | Données de la veille           | Recalculer de temps en temps pour comparer |
| Suggestions          | Calcul lourd         | Suggestions calculées à l'avance                     | Peuvent être en retard         | Les refaire depuis les amitiés             |
| 50 derniers messages | Lecture très fréquente | Copier le pseudo de l'auteur dans le message       | Pseudo faux si l'auteur le change | Garder `id_auteur` pour retrouver le bon pseudo |

**Accès où je refuse : vérifier qu'un utilisateur peut écrire.** Une copie en retard laisserait écrire un utilisateur exclu. On lit toujours EST_MEMBRE.

---

## Phase 3

### 3.a Autopsie de 2015

- À 100 M de messages, les données (30 Go) et l'index (4 Go) ne tiennent plus dans les 16 Go de RAM.
- MongoDB trouve vite les 50 messages grâce à l'index, qui est en RAM.
- Mais les messages sont rangés dans l'ordre d'arrivée, mélangés avec ceux des autres salons. Pour en lire 50, il faut aller en chercher jusqu'à 50 à des endroits différents du disque.
- Si les messages sont en cache, c'est rapide. Sinon c'est lent. Les temps de réponse deviennent donc imprévisibles.
- **Le serveur à dominante vocale est le pire cas** : très peu de messages, donc jamais en cache, et ce sont de vieux messages. Chaque affichage va sur le disque.

### 3.b Qui prétend au rôle ?

| | PostgreSQL | MongoDB | Cassandra | Redis |
| --- | --- | --- | --- | --- |
| Modèle de données | Tables | Documents | Colonnes (messages d'un salon rangés ensemble) | Clé-valeur |
| Si les données dépassent la RAM | Lectures dispersées sur le disque | Pareil (problème de 2015) | Bien : les 50 messages sont au même endroit | Impossible : tout doit tenir en RAM |
| Passage à l'échelle | Difficile | Possible mais écarté par Discord | Prévu dès le départ | Possible mais coûteux |
| Ce qu'on perd | Rien | Jointures | Jointures, transactions, requêtes libres | Données sur disque |

**Par profil de serveur :**
- Vocal et textuel privé : seul Cassandra lit les 50 messages au même endroit.
- Grand serveur public : tout marche (données en cache). Redis peut servir de cache.

### 3.c Clé de partition

**1. Taille de partition pour 10 M de messages par an** (10 M × 300 octets = 3 Go par an)

| Option           | Calcul                              | Taille  | Moins de 100 Mo ? |
| ---------------- | ----------------------------------- | ------- | ----------------- |
| A (salon)        | 10 M × 300 octets                   | 3 Go    | Non               |
| B (N = 10 jours) | 10 M / 365 × 10 ≈ 274 000 × 300 octets | ~82 Mo | Oui               |
| C (jour)         | 10 M / 365 ≈ 27 400 × 300 octets    | ~8 Mo   | Oui               |

→ **L'option A dépasse la limite de 100 Mo.**

**2. Salon de 1 000 messages par an, pour obtenir 50 messages**
- B : 1 000 / 365 × 10 ≈ 27 messages par fenêtre, donc **2 partitions**
- C : 1 000 / 365 ≈ 2,7 messages par jour, donc 50 / 2,7 ≈ **18 partitions**
- Plus il y a de partitions à lire, plus la lecture est longue. Beaucoup de ces fenêtres sont vides.

**3. Un N bon pour les deux ?** Non. Un gros salon veut des petites fenêtres (pour rester sous 100 Mo), un petit salon veut des grandes (pour lire peu de partitions). L'article prend un compromis : des fenêtres d'environ 10 jours. Pour éviter de lire des fenêtres vides, on retient quelles fenêtres contiennent des messages.

**4. Pourquoi `message_id` plutôt que l'horodatage ?** Deux messages peuvent avoir le même horodatage. Dans Cassandra, deux lignes avec la même clé s'écrasent : on perdrait un message. Le `message_id` est unique et classé par date.

### 3.d Modes de défaillance

| Incident                           | Ce qui se passe dans le moteur                          | Prévisible ?                                    | Garde-fou / alerte                                   |
| ---------------------------------- | ------------------------------------------------------- | ----------------------------------------------- | ---------------------------------------------------- |
| NULL écrits                        | Chaque NULL crée une tombstone (~12 par message)        | Oui : 16 colonnes pour 4 valeurs                | N'écrire que les valeurs non nulles                  |
| Salon avec des millions de suppressions | Lire le salon oblige à parcourir des millions de tombstones | Oui : on sait qu'on peut supprimer des messages | Garder les tombstones moins longtemps ; retenir les fenêtres vides |
| Partition chaude                   | Un gros serveur sollicite toujours les mêmes nœuds      | Oui : les 3 profils de serveurs sont très inégaux | Alerte sur le temps de réponse par nœud              |
| Pauses du ramasse-miettes          | Le moteur se met en pause pour nettoyer la mémoire, parfois un nœud doit être redémarré à la main | Oui : c'est connu pour ce type de moteur | Alerte sur la durée des pauses ; choisir un moteur sans ramasse-miettes (ScyllaDB) |

---

## Phase 4

### 4.a Carte des besoins

| Besoin                           | Moteur        | Paradigme   | Contrainte décisive                                  | Source de vérité ? | Comment la donnée y arrive     | Ce qu'on accepte de perdre        |
| -------------------------------- | ------------- | ----------- | ---------------------------------------------------- | ------------------ | ------------------------------ | --------------------------------- |
| Comptes, serveurs, appartenances | PostgreSQL    | Relationnel | Email unique, clés étrangères, rôles (CHECK)         | Oui                | Écriture directe               | Passage à l'échelle facile        |
| Messages + pièce jointe          | Cassandra     | Colonnes    | 50 derniers messages au même endroit ; 100 Mo max par partition | Oui     | Écriture directe               | Jointures, transactions           |
| Vérification du droit d'écrire   | PostgreSQL    | Relationnel | Doit toujours être exact                             | Oui                | Lecture directe                | Rien                              |
| Présence                         | Redis         | Clé-valeur  | Disparaît seule après 5 minutes                      | Oui (éphémère)     | Écriture directe à chaque signe de vie | Tout si Redis redémarre   |
| Amitiés                          | PostgreSQL    | Relationnel | Une seule fois par paire (UNIQUE)                    | Oui                | Écriture directe               | Rien                              |
| Suggestions                      | Neo4j         | Graphe      | Parcours d'amis d'amis                               | Non (copie)        | Copie des amitiés chaque nuit  | Suggestions parfois en retard     |
| Tableau de bord                  | Cassandra     | Colonnes    | Une mise à jour par jour suffit                      | Non (calculé)      | Calcul chaque nuit depuis les messages | Données de la veille      |

### 4.b Schéma

```
                       écriture directe (immédiat)
              ┌──────────────────────────────────────► PostgreSQL
              │                                         (comptes, serveurs,
 Application ─┤                                          membres, amitiés)
              │
              ├── écriture directe (immédiat) ────────► Cassandra  (messages, stats)
              │
              └── écriture directe, expire à 5 min ───► Redis      (présence)

 PostgreSQL ── copie chaque nuit (amitiés) ───────────► Neo4j      (suggestions)
 Cassandra  ── calcul chaque nuit (messages du jour) ─► Cassandra  (stats du tableau de bord)
```

### 4.c Trois décisions

**Décision 1 : messages dans Cassandra (partition = salon + fenêtre de 10 jours, tri par `message_id`)**
- **Contexte** : les 50 derniers messages sont la requête la plus fréquente. À 100 M de messages, les données ne tiennent plus en RAM.
- **Options écartées** : PostgreSQL et MongoDB (lectures dispersées sur le disque, comme en 2015) ; Redis (tout doit tenir en RAM) ; clé A (partition de 3 Go).
- **Conséquences** : lecture rapide et prévisible. On perd les jointures et les transactions. Risques : tombstones, partition chaude.
- **Ce qui nous ferait changer d'avis** : un temps de réponse (p95) durablement au-dessus de 80 ms.

**Décision 2 : présence dans Redis**
- **Contexte** : la présence disparaît après 5 minutes sans signe de vie, et on n'a pas besoin de la garder.
- **Options écartées** : PostgreSQL (il faudrait coder le nettoyage, et chaque signe de vie serait écrit pour rien).
- **Conséquences** : la suppression est automatique. Si Redis redémarre, on perd les présences, mais elles reviennent en 5 minutes. Un moteur de plus à gérer.
- **Ce qui nous ferait changer d'avis** : l'équipe ne peut pas gérer un moteur de plus, ou on veut garder un historique de présence.

**Décision 3 : tableau de bord calculé chaque nuit**
- **Contexte** : compter les messages et les auteurs par jour coûte cher, et une mise à jour par jour suffit.
- **Options écartées** : calcul à chaque consultation (il faudrait relire tous les messages du serveur) ; mise à jour à chaque message (alourdit l'écriture, déjà ~4 200/s au pic).
- **Conséquences** : lecture très rapide, mais les données sont celles de la veille. Si le calcul échoue, le tableau reste ancien.
- **Ce qui nous ferait changer d'avis** : si le calcul direct prend moins d'une seconde, la table de stats ne sert plus à rien.

### 4.d Le risque principal : les amitiés copiées dans Neo4j

- **Divergence** : une amitié est supprimée dans PostgreSQL mais reste dans Neo4j.
- **Qui s'en aperçoit, quand** : l'utilisateur, quand on lui suggère les serveurs d'un ancien ami. Parfois personne ne s'en aperçoit.
- **Dommage** : faible pour le confort, mais gênant pour la vie privée (un ancien ami voit les serveurs que l'on rejoint).
- **Détection** : chaque nuit, comparer le nombre d'amitiés dans PostgreSQL avec le nombre de liens dans Neo4j.
- **Réparation** : refaire la copie depuis PostgreSQL, qui est la source de vérité.

### 4.e La version minimale (2 moteurs)

**Je garde PostgreSQL et Redis.**
- PostgreSQL : source de vérité pour tout le reste.
- Redis : la présence, car la suppression automatique après 5 minutes est difficile à avoir ailleurs.

**Besoins orphelins :**

| Besoin          | Comment dans PostgreSQL                                              |
| --------------- | -------------------------------------------------------------------- |
| Messages        | Table MESSAGE avec l'index (id_salon, id_message DESC) : suffisant pour 300 000 messages |
| Pièces jointes  | Colonnes `pj_type`, `pj_url`, `pj_nom`                               |
| Suggestions     | Requête avec deux jointures sur ETRE_AMI (15 000 amitiés)            |
| Tableau de bord | Requête de comptage lancée chaque nuit, résultat gardé dans une table |

**Signaux pour ajouter un moteur :**

| Moteur ajouté             | Signal mesurable                                                                      |
| ------------------------- | ------------------------------------------------------------------------------------- |
| 3e : Cassandra (messages) | Autour de 100 M de messages (les données dépassent la RAM), ou temps de réponse (p95) des 50 derniers messages > 80 ms |
| 4e : Neo4j (suggestions)  | Suggestions plus lentes qu'une seconde, ou beaucoup plus d'amitiés                    |

---

## Phase 5

1. **Je pense que** Cassandra sera **équivalent** à PostgreSQL **pour** afficher les 50 derniers messages, **d'un facteur d'environ 1**, **parce que** avec 300 000 messages tout tient en RAM.
   *Si elle est fausse* : soit l'index PostgreSQL n'est pas utilisé comme prévu, soit Cassandra a un coût fixe (réseau, Docker) qui domine.

2. **Je pense que** Redis sera **plus rapide** que PostgreSQL **pour** mettre à jour la présence, **d'un facteur d'environ 5**, **parce que** Redis écrit en mémoire sans écriture durable.
   *Si elle est fausse* : le réseau Docker domine, donc le moteur n'est pas le facteur limitant.

3. **Je pense que** Neo4j sera **plus rapide** que PostgreSQL **pour** les amis d'amis, **d'un facteur d'environ 3**, **parce que** un graphe suit des liens directs au lieu de faire des jointures.
   *Si elle est fausse* : avec 15 000 amitiés, la jointure suffit, donc Neo4j n'est pas justifié (cela confirme la version minimale).

4. **Je pense que** lire les 50 derniers messages d'un **salon vocal** (peu de messages) sera **plus lent** que pour un salon actif dans Cassandra, **d'un facteur d'environ 3 à 10**, **parce que** il faut lire plusieurs fenêtres l'une après l'autre.
   *Si elle est fausse* : les fenêtres vides coûtent peu, ou mes salons de test ne sont pas assez peu actifs.

5. **Je pense que** lire la table de stats du tableau de bord sera **plus rapide** que compter directement les messages dans PostgreSQL, **d'un facteur d'environ 50**, **parce que** on lit quelques lignes au lieu de parcourir tous les messages.
   *Si elle est fausse* : à 300 000 messages le calcul direct suffit, la table de stats n'est pas encore utile.
