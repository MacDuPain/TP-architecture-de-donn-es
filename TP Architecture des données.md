## Phase 0
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

## Phase 2
## Phase 3
## Phase 4
## Phase 5