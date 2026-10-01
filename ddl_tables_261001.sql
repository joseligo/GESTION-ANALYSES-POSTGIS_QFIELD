-- =====================================================================
-- DDL DE RÉFÉRENCE — TABLES
-- Projet : prélèvements de sol (PostGIS Supabase / QGIS / QField)
-- Version : v1 — 2026-10-01
-- À exécuter AVANT ddl_fonctions_triggers_261001.sql
-- =====================================================================
--
-- ORGANISATION EN SCHÉMAS
--   public        → extension PostGIS uniquement (ne rien y créer)
--   referentiel   → données communes réutilisables par d'autres projets
--                   tae, ctc, depots, exploitation
--   parcellaire   → parcelles (Smag aujourd'hui, Télépac demain)
--   analyses_sol  → projet prélèvements de sol
--                   commandes, demandes_analyse, prelevements_sol, resultats_analyse
--
-- RÈGLE DE DÉPENDANCE (toujours dans ce sens, jamais l'inverse)
--   analyses_sol → parcellaire → referentiel
--
-- CONVENTIONS
--   · Clés primaires uuid (gen_random_uuid() en base ;
--     prévoir uuid() en valeur par défaut côté QGIS pour le hors ligne)
--   · Liens entre tables via les codes métier (code_expl, code_tech, code_site)
--   · Géométries en Lambert-93 (SRID 2154)
--   · Valeurs de statut en snake_case
--   · Aucune suppression en cascade sur la chaîne commande → prélèvement → résultat
--   · RLS activé sans politique : sans effet avec l'utilisateur postgres,
--     à définir si un utilisateur dédié QField est créé
--
-- PÉRIMÈTRE V1 — HORS SCOPE (prévu pour plus tard)
--   · Commandes sans point : la fonction de rattachement le gère déjà.
--     Pour l'activer, une seule ligne :
--       ALTER TABLE analyses_sol.commandes ALTER COLUMN geom DROP NOT NULL;
--     Reste à valider côté QField : ajout d'une géométrie sur une commande
--     retrouvée via la fiche exploitation.
--   · Table horizons (plusieurs profondeurs par prélèvement)
--   · Clients non sociétaires
--   · QFieldCloud hors ligne (mode hybride)
--   · Comptes utilisateurs individuels
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS referentiel  AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS parcellaire  AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS analyses_sol AUTHORIZATION postgres;


-- #####################################################################
-- SCHÉMA referentiel
-- #####################################################################

-- ---------------------------------------------------------------------
-- referentiel.ctc — techniciens CTC
-- ---------------------------------------------------------------------
CREATE TABLE referentiel.ctc (
	id          uuid        DEFAULT gen_random_uuid() NOT NULL,
	code_tech   text        NOT NULL,
	nom_tech    text        NOT NULL,
	prenom_tech text        NOT NULL,
	mail        text        NOT NULL,
	created_at  timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT ctc_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX idx_ctc_code_tech ON referentiel.ctc USING btree (code_tech);
ALTER TABLE referentiel.ctc ENABLE ROW LEVEL SECURITY;


-- ---------------------------------------------------------------------
-- referentiel.tae — Techniciens Agro-Environnement
-- ---------------------------------------------------------------------
CREATE TABLE referentiel.tae (
	id          uuid        DEFAULT gen_random_uuid() NOT NULL,
	code_tech   text        NOT NULL,
	nom_tech    text        NOT NULL,
	prenom_tech text        NOT NULL,
	mail        text        NOT NULL,
	created_at  timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT tae_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX idx_tae_code_tech ON referentiel.tae USING btree (code_tech);
ALTER TABLE referentiel.tae ENABLE ROW LEVEL SECURITY;


-- ---------------------------------------------------------------------
-- referentiel.depots — sites physiques
-- ---------------------------------------------------------------------
CREATE TABLE referentiel.depots (
	id         uuid        DEFAULT gen_random_uuid() NOT NULL,
	code_site  text        NOT NULL,
	nom_site   text        NOT NULL,
	insee      text        NOT NULL,
	commune    text        NOT NULL,
	geom       public.geometry(point, 2154) NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT depots_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX idx_depots_code_site ON referentiel.depots USING btree (code_site);
CREATE INDEX idx_depots_geom ON referentiel.depots USING gist (geom);
ALTER TABLE referentiel.depots ENABLE ROW LEVEL SECURITY;


-- ---------------------------------------------------------------------
-- referentiel.exploitation — sociétaires
-- Une exploitation a exactement un TAE, un CTC et un dépôt (FK par code).
-- Point d'entrée du parcours QField : la fiche exploitation affiche
-- ses commandes et ses demandes (relations sur code_expl).
-- ---------------------------------------------------------------------
CREATE TABLE referentiel.exploitation (
	id                   uuid        DEFAULT gen_random_uuid() NOT NULL,
	code_expl            text        NOT NULL,
	libelle_exploitation text        NOT NULL,
	pacage               text        NULL,
	mail                 text        NULL,
	tel                  text        NULL,
	adresse_1            text        NULL,
	adresse_2            text        NULL,
	code_postal          text        NULL,
	commune              text        NULL,
	code_insee           text        NULL,
	tae                  text        NULL,
	ctc                  text        NULL,
	depot                text        NULL,
	created_at           timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT exploitation_pkey PRIMARY KEY (id),
	CONSTRAINT exploitation_ctc_fkey   FOREIGN KEY (ctc)   REFERENCES referentiel.ctc(code_tech)    ON DELETE SET NULL,
	CONSTRAINT exploitation_depot_fkey FOREIGN KEY (depot) REFERENCES referentiel.depots(code_site) ON DELETE SET NULL,
	CONSTRAINT exploitation_tae_fkey   FOREIGN KEY (tae)   REFERENCES referentiel.tae(code_tech)    ON DELETE SET NULL
);
CREATE UNIQUE INDEX idx_exploitation_code_expl ON referentiel.exploitation USING btree (code_expl);
ALTER TABLE referentiel.exploitation ENABLE ROW LEVEL SECURITY;


-- #####################################################################
-- SCHÉMA parcellaire
-- #####################################################################

-- ---------------------------------------------------------------------
-- parcellaire.parcelles
-- · geom FACULTATIVE : une parcelle Smag peut exister sans être
--   cartographiée ; elle reste liable à une commande mais est ignorée
--   par la recherche spatiale.
-- · id_logiciel_interne = identifiant Smag, unique PAR CAMPAGNE.
--   L'import des commandes Smag retrouve parcelles.id via
--   (campagne, id_logiciel_interne).
-- · source_origine : système d'où provient la parcelle.
-- ---------------------------------------------------------------------
CREATE TABLE parcellaire.parcelles (
	id                  uuid          DEFAULT gen_random_uuid() NOT NULL,
	code_expl           text          NULL,
	campagne            int4          NOT NULL,
	num_ilot            text          NULL,
	num_parcelle        text          NULL,
	libelle             text          NULL,
	surface             numeric(10,2) NULL,
	culture             text          NULL,
	culture_n1          text          NULL,
	culture_n2          text          NULL,
	geom                public.geometry(polygon, 2154) NULL,
	id_logiciel_interne text          NULL,
	source_origine      text          NULL,
	created_at          timestamptz   DEFAULT now() NOT NULL,
	CONSTRAINT parcelles_pkey PRIMARY KEY (id),
	CONSTRAINT parcelles_code_expl_fkey FOREIGN KEY (code_expl) REFERENCES referentiel.exploitation(code_expl) ON DELETE SET NULL
);
CREATE INDEX idx_parcelles_geom ON parcellaire.parcelles USING gist (geom);
CREATE UNIQUE INDEX idx_parcelles_campagne_id_logiciel
	ON parcellaire.parcelles USING btree (campagne, id_logiciel_interne)
	WHERE (id_logiciel_interne IS NOT NULL);
ALTER TABLE parcellaire.parcelles ENABLE ROW LEVEL SECURITY;


-- #####################################################################
-- SCHÉMA analyses_sol
-- #####################################################################

-- ---------------------------------------------------------------------
-- analyses_sol.commandes — commandes d'analyse de sol
--
-- statut : a_faire | terrain | realise | annule
--   · terrain  = commande créée sur place dans QField
--   · realise  = UNIQUEMENT via la création du prélèvement (trigger) ;
--                un passage manuel est refusé par la base
--   · annule   = aucun prélèvement ne peut y être ajouté
--
-- statut_rattachement (géré par trigger, porte aussi l'origine) :
--   · logiciel       = import Smag, parcelle fournie (cartographiée ou non)
--   · logiciel_modif = commande Smag dont le point a changé de parcelle
--                      (ou est sorti de toute parcelle) ; trace conservée
--   · manuel         = commande terrain, parcelle trouvée par le point
--   · non_rattachee  = commande terrain, point hors parcelle
--
-- parcelle_id : jamais modifié directement (lecture seule dans les
--   formulaires) ; déterminé par l'import ou par le point.
--
-- Snapshot éditable pour le labo (nom_parcelle, culture, culture_n1,
--   culture_n2, surface) : complété depuis la parcelle, rafraîchi quand
--   la parcelle change, conservé sinon.
--
-- geom : OBLIGATOIRE en v1 (voir en-tête pour l'activer en facultatif).
-- ---------------------------------------------------------------------
CREATE TABLE analyses_sol.commandes (
	commande_id          uuid          DEFAULT gen_random_uuid() NOT NULL,
	id_commande_logiciel text          NULL,
	code_expl            text          NULL,
	campagne             int4          NOT NULL,
	statut               text          DEFAULT 'a_faire'::text NOT NULL,
	parcelle_id          uuid          NULL,
	statut_rattachement  text          DEFAULT 'non_rattachee'::text NOT NULL,
	nom_parcelle         text          NULL,
	culture              text          NULL,
	culture_n1           text          NULL,
	culture_n2           text          NULL,
	surface              numeric(10,2) NULL,
	geom                 public.geometry(point, 2154) NOT NULL,
	type_analyse         text          NULL,
	created_at           timestamptz   DEFAULT now() NOT NULL,
	CONSTRAINT commandes_pkey PRIMARY KEY (commande_id),
	CONSTRAINT commandes_statut_check
		CHECK (statut IN ('a_faire', 'terrain', 'realise', 'annule')),
	CONSTRAINT commandes_statut_rattachement_check
		CHECK (statut_rattachement IN ('logiciel', 'logiciel_modif', 'manuel', 'non_rattachee')),
	CONSTRAINT commandes_code_expl_fkey   FOREIGN KEY (code_expl)   REFERENCES referentiel.exploitation(code_expl) ON DELETE SET NULL,
	CONSTRAINT commandes_parcelle_id_fkey FOREIGN KEY (parcelle_id) REFERENCES parcellaire.parcelles(id)         ON DELETE SET NULL
);
CREATE INDEX idx_commandes_geom     ON analyses_sol.commandes USING gist  (geom);
CREATE INDEX idx_commandes_parcelle ON analyses_sol.commandes USING btree (parcelle_id);
CREATE UNIQUE INDEX idx_id_commandes_logiciel
	ON analyses_sol.commandes USING btree (id_commande_logiciel)
	WHERE (id_commande_logiciel IS NOT NULL);
ALTER TABLE analyses_sol.commandes ENABLE ROW LEVEL SECURITY;


-- ---------------------------------------------------------------------
-- analyses_sol.demandes_analyse — demandes sans parcelle encore définie
-- · Une ligne = UNE analyse demandée (4 analyses = 4 lignes)
-- · statut : a_prevoir | termine (termine => commande_id obligatoire)
-- · prelevement : qui prélève (Agri = l'agriculteur, CAVAC = un technicien)
-- · Une commande ne peut satisfaire qu'une seule demande
-- ---------------------------------------------------------------------
CREATE TABLE analyses_sol.demandes_analyse (
	demande_id   uuid        DEFAULT gen_random_uuid() NOT NULL,
	code_expl    text        NULL,
	campagne     int4        NOT NULL,
	commentaire  text        NULL,
	type_analyse text        NULL,
	prelevement  text        NULL,
	statut       text        DEFAULT 'a_prevoir'::text NOT NULL,
	commande_id  uuid        NULL,
	created_at   timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT demandes_analyse_pkey PRIMARY KEY (demande_id),
	CONSTRAINT demandes_analyse_prelevement_check
		CHECK (prelevement IN ('Agri', 'CAVAC')),
	CONSTRAINT demandes_analyse_statut_check
		CHECK (statut IN ('a_prevoir', 'termine')),
	CONSTRAINT demandes_analyse_termine_commande_check
		CHECK (statut <> 'termine' OR commande_id IS NOT NULL),
	CONSTRAINT demandes_analyse_code_expl_fkey   FOREIGN KEY (code_expl)   REFERENCES referentiel.exploitation(code_expl) ON DELETE SET NULL,
	CONSTRAINT demandes_analyse_commande_id_fkey FOREIGN KEY (commande_id) REFERENCES analyses_sol.commandes(commande_id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX idx_demandes_analyse_commande_id
	ON analyses_sol.demandes_analyse USING btree (commande_id)
	WHERE (commande_id IS NOT NULL);
ALTER TABLE analyses_sol.demandes_analyse ENABLE ROW LEVEL SECURITY;


-- ---------------------------------------------------------------------
-- analyses_sol.prelevements_sol
-- · Un seul prélèvement par commande ; créé depuis la fiche de la
--   commande (widget de relation). Sa création passe la commande
--   en 'realise' (trigger).
-- · statut : en_attente | preleve | labo | analyse
--   code_barre obligatoire dès que statut <> en_attente
--   (prévoir 'en_attente' en valeur par défaut côté QGIS : un champ
--   vide envoyé en NULL serait refusé)
-- · preleveur : texte libre (technicien ou agriculteur)
-- · Suppression d'une commande refusée si elle a un prélèvement
-- ---------------------------------------------------------------------
CREATE TABLE analyses_sol.prelevements_sol (
	id               uuid        DEFAULT gen_random_uuid() NOT NULL,
	commande_id      uuid        NOT NULL,
	geom             public.geometry(point, 2154) NOT NULL,
	date_prelevement date        DEFAULT CURRENT_DATE NOT NULL,
	laboratoire      text        DEFAULT 'LabO'::text NULL,
	code_barre       text        NULL,
	statut           text        DEFAULT 'en_attente'::text NOT NULL,
	date_labo        date        NULL,
	date_resultat    date        NULL,
	preleveur        text        NULL,
	created_at       timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT prelevements_sol_pkey PRIMARY KEY (id),
	CONSTRAINT prelevements_sol_code_barre_key  UNIQUE (code_barre),
	CONSTRAINT prelevements_sol_commande_id_key UNIQUE (commande_id),
	CONSTRAINT prelevements_sol_statut_check
		CHECK (statut IN ('en_attente', 'preleve', 'labo', 'analyse')),
	CONSTRAINT ck_code_barre_si_preleve
		CHECK (statut = 'en_attente' OR code_barre IS NOT NULL),
	CONSTRAINT prelevements_sol_commande_id_fkey FOREIGN KEY (commande_id) REFERENCES analyses_sol.commandes(commande_id) ON DELETE RESTRICT
);
CREATE INDEX idx_prelevements_geom ON analyses_sol.prelevements_sol USING gist (geom);
ALTER TABLE analyses_sol.prelevements_sol ENABLE ROW LEVEL SECURITY;


-- ---------------------------------------------------------------------
-- analyses_sol.resultats_analyse
-- · Une ligne par prélèvement
-- · Paramètres standards en colonnes + autres_resultats (jsonb)
--   pour tout paramètre non prévu
-- · numero_echantillon_labo toujours fourni par le labo
-- · Suppression d'un prélèvement refusée s'il a des résultats
-- ---------------------------------------------------------------------
CREATE TABLE analyses_sol.resultats_analyse (
	id                      uuid    DEFAULT gen_random_uuid() NOT NULL,
	prelevement_id          uuid    NOT NULL,
	numero_echantillon_labo text    NOT NULL,
	ph                      numeric NULL,
	matiere_organique_pct   numeric NULL,
	p2o5_mg_kg              numeric NULL,
	k2o_mg_kg               numeric NULL,
	mgo_mg_kg               numeric NULL,
	cec_meq_100g            numeric NULL,
	autres_resultats        jsonb   NULL,
	CONSTRAINT resultats_analyse_pkey PRIMARY KEY (id),
	CONSTRAINT resultats_analyse_prelevement_id_key UNIQUE (prelevement_id),
	CONSTRAINT resultats_analyse_prelevement_id_fkey FOREIGN KEY (prelevement_id) REFERENCES analyses_sol.prelevements_sol(id) ON DELETE RESTRICT
);
ALTER TABLE analyses_sol.resultats_analyse ENABLE ROW LEVEL SECURITY;
