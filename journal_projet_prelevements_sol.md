# Suivi de projet — Module de saisie terrain (prélèvements de sol)

Portfolio personnel : base PostGIS (Supabase) + module de saisie terrain QField, pour l'enregistrement des prélèvements d'analyses de sol, en lien avec le référentiel parcellaire.

Format changelog — entrées les plus récentes en haut. Ajouter une nouvelle section datée à chaque session de travail.

---

## 2026-09-22

**Création de la BDD — Supabase**
- Connexion via GitHub
- Projet créé en région Irlande (eu-west-1) — pas de souci de latence pour l'usage prévu ; la région ne peut pas être changée après coup, seul le mot de passe DB est modifiable à tout moment (Project Settings → Database)
- Extension PostGIS activée, installée dans le schéma `gis` (pas le défaut `extensions`) → `set search_path = public, gis, extensions;` en tête de script pour éviter de préfixer chaque type/fonction
- Extensions additionnelles (`postgis_topology`, `postgis_raster`...) : non activées, pas nécessaires pour un usage 100% vectoriel sans topologie stricte

**Choix du SRID**
- Lambert-93 (EPSG:2154) retenu comme SRID de stockage, plutôt que WGS84 (4326) : calculs directs en mètres (ST_Area, ST_Distance), cohérent avec le référentiel RPG/Télépac déjà manipulé côté QGIS
- Les coordonnées GPS terrain (WGS84) sont reprojetées à la volée par QGIS/QField à l'écriture — aucune manipulation manuelle nécessaire

**Script SQL — tables créées**
- `parcelles` — référentiel parcellaire (stub en attendant le branchement complet sur l'import Télépac)
- `prelevements_sol` — un enregistrement = un point de prélèvement terrain
- `horizons` — profondeurs multiples par prélèvement (0-30, 30-60 cm...) — *à voir si besoin de garder*
- `resultats_analyse` — résultats labo, colonnes fixes (pH, matière organique, P2O5, K2O, MgO, CEC) + `jsonb` de secours pour un paramètre exotique
- `commandes_analyse_sol` — commandes créées dans le logiciel de suivi parcellaire interne, à valider terrain via QField

**Détails de conception — parcelles**
- `parcelle_id` nullable sur `prelevements_sol` + champ `parcelle_libre` en repli, pour ne pas bloquer la saisie terrain si la parcelle n'existe pas encore en base
- `id_logiciel_interne` + `source_origine` ajoutés sur `parcelles`, pour distinguer les parcelles importées via XML Télépac de celles issues du logiciel de suivi parcellaire interne
- Rattachement spatial automatique : fonction `rattacher_prelevements_orphelins()` (ST_Contains) pour lier les prélèvements orphelins aux parcelles existantes
- Validation du rattachement : champ `statut_rattachement` (`non_rattache` / `auto_suggere` / `valide` / `manuel`) + fonction `valider_rattachement_parcelle()` — le rattachement auto reste "à vérifier" tant qu'il n'est pas confirmé

**Détails de conception — résultats analyse**
- Choix colonnes fixes plutôt que modèle clé-valeur (plus lisible pour un socle de paramètres standard en analyse de sol)
- `numero_echantillon_labo` positionné sur `resultats_analyse` (et non `prelevements_sol`) : cet identifiant n'est connu qu'à réception par le labo, pas au moment du terrain

**Détails de conception — terrain / sacs**
- Champ `code_barre` sur `prelevements_sol`, scanné nativement via le widget QField (pas de développement custom), avec contrainte unique
- Fonction `importer_resultat_par_code_barre()` : rapproche automatiquement un résultat labo à son prélèvement via le code-barres du sac — à confirmer avec le labo s'ils peuvent renvoyer ce code-barres dans leur fichier de résultats

**Trigger**
- `valider_commande_analyse()` — quand le statut d'une commande passe à `realise` (validation terrain dans QField), crée automatiquement la ligne correspondante dans `prelevements_sol` et la lie via `prelevement_id`. Pas de ressaisie manuelle entre les deux tables.

**Sécurité**
- Row Level Security activé sur toutes les tables, sans policy pour l'instant (bloque l'accès via l'API REST Supabase par défaut) — sans effet sur la connexion PostgreSQL directe utilisée par QGIS/QField

**À tester**
- [ ] Dessin de géométries directement dans QGIS (connexion PostgreSQL)
- [ ] Import de données via SQL direct (WKT)
- [ ] Import de données via CSV (avec reprojection 4326 → 2154)
- [ ] Validation d'une commande dans QField → vérifier la création automatique du prélèvement lié
- [ ] Scan de code-barres via QField

**Idées à creuser plus tard (pas bloquantes)**
- Table pour les espèces/cultures présentes sur la parcelle
- Confirmation avec le labo sur le format d'échange du code-barres
- Décider si `horizons` reste une table à part ou se fusionne dans `prelevements_sol`

## 2026-09-23

**Modification de la BDD — Supabase**
- Déplacement de PostGis dans le schéma `public` plutôt que dans `gis` : évite les paramétrages de search_path et les incompatibilités de fonction. Compatibilité maximale avec tous les outils de l'écosystème.
    `alter extension postgis set schema public`;

**test enregistrement dans BDD** :**
- dessin dans QGIS : ok pour commandes_analyse_sol
- problème lors du passage à "réalisé" : après suppression de la ligne problématique, ça fonctionne....

**Idée à creuser**
- autocomplétion du champ `source_origine` de la table `parcelles` : dessin, logiciel suivi parcellaire, télépac (à voir si besoin cette dernière catégorie)
- liste de choix pour le remplissage de certains champs

## 2026-09-25

**Réflexion sur le MCD**
- à reprendre pour avoir un lien `commandes`-> `prélèvement` -> `résultats`
- gestion des données parcelles avec anticipation comportement de mise à jour (correction manuelle vs update de la base)
- modifier `rattacher_prelevements_orphelin` en `rattacher_commande_orpheline`
- traiter les commandes à l'exploitation sans parcelle défini (on sait juste que GAEC Machin veut 2 analyses)
- création table `exploitation`
- intégrer table `dépôt` et `technicien`
- laisser le champ `préleveur` à la saisie libre