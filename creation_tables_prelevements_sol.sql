-- ============================================================
-- Module de saisie terrain — Prélèvements de sol
-- Schéma PostGIS pour Supabase
-- ============================================================

-- Extension nécessaire (déjà activée)
-- create extension if not exists postgis with schema gis;

-- postgis est dans le schéma "gis", pgcrypto (gen_random_uuid) dans "extensions" :
-- on les ajoute au search_path pour ne pas avoir à préfixer chaque type/fonction
--set search_path = public, gis, extensions;

-- ------------------------------------------------------------
-- Table DEPOT
-- Liste des dépôts 
-- ------------------------------------------------------------
create table if not exists depots (
    id                      uuid primary key default gen_random_uuid(),
    code_site               text not null,
    nom_site                text not null,
    insee                   text not null,
    commune                 text not null,
    geom                    geometry(Point, 2154),
    created_at              timestamptz not null default now()
);

create index if not exists idx_depots_geom
    on depots using gist (geom);

create unique index if not exists idx_depots_code_site
    on depots (code_site);

-- ------------------------------------------------------------
-- Table TAE
-- Liste des TAE (Techniciens Agro-Environnement)
-- ------------------------------------------------------------
create table if not exists tae (
    id                      uuid primary key default gen_random_uuid(),
    code_tech               text not null,
    nom_tech                text not null,
    prenom_tech                  text not null,
    mail                 text not null,
    created_at              timestamptz not null default now()
);

create unique index if not exists idx_tae_code_tech
    on tae (code_tech);

-- ------------------------------------------------------------
-- Table CTC
-- Liste des CTC (Techniciens Agro-Environnement)
-- ------------------------------------------------------------
create table if not exists ctc (
    id                      uuid primary key default gen_random_uuid(),
    code_tech               text not null,
    nom_tech                text not null,
    prenom_tech                  text not null,
    mail                 text not null,
    created_at              timestamptz not null default now()
);

create unique index if not exists idx_ctc_code_tech
    on ctc (code_tech);

-- ------------------------------------------------------------
-- Table Exploitation
-- Liste des exploitations (agriculteurs)
-- ------------------------------------------------------------
create table if not exists exploitation (
    id                      uuid primary key default gen_random_uuid(),
    code_expl              text not null,
    libelle_exploitation                text not null,
    pacage                  text,
    mail                  text,
    tel                 text,
    adresse_1                 text,
    adresse_2                 text,
    code_postal                 text,
    commune                 text,
    code_insee                 text,
    tae                 text references tae(code_tech) on delete set null,
    ctc                 text references ctc(code_tech) on delete set null,
    depot                 text references depots(code_site) on delete set null,
    created_at              timestamptz not null default now()
);

create unique index if not exists idx_exploitation_code_expl
    on exploitation (code_expl);

-- ------------------------------------------------------------
-- Table PARCELLES
-- Référentiel parcellaire (import depuis logiciel de suivi parcellaire interne ; import Télépac ou saisie manuelle)
-- ------------------------------------------------------------
create table if not exists parcelles (
    id                      uuid primary key default gen_random_uuid(),
    code_expl               text references exploitation(code_expl) on delete set null,
    campagne                integer not null,
    num_ilot                text,
    num_parcelle            text,
    libelle                 text,
    surface                 numeric(10,2),
    culture                 text,
    culture_n1              text,
    culture_n2              text,
    geom                    geometry(Polygon, 2154) not null,
    id_logiciel_interne     text,   -- identifiant du logiciel de suivi parcellaire interne
    source_origine          text,   -- 'telepac_xml' / 'logiciel_interne' / 'saisie_manuelle'
    created_at              timestamptz not null default now()
);

create index if not exists idx_parcelles_geom
    on parcelles using gist (geom);

-- Un id_logiciel_interne donné ne doit pas se retrouver sur deux parcelles,
-- mais les lignes qui n'en ont pas encore (import Télépac non rapproché) restent libres
create unique index if not exists idx_parcelles_id_logiciel
    on parcelles (id_logiciel_interne)
    where id_logiciel_interne is not null;
-- ------------------------------------------------------------
-- Table Commandes
-- 
-- ------------------------------------------------------------

create table if not exists commandes (
    commande_id             uuid primary key default gen_random_uuid(),
    id_commande_logiciel     text,   -- identifiant du logiciel de suivi parcellaire interne
    code_expl                text references exploitation(code_expl) on delete set null,
    campagne                 integer not null,
    statut                   text not null default 'a_faire'
                                check (statut in ('a_faire', 'terrain', 'realise', 'annule')),
    parcelle_id              uuid references parcelles(id) on delete set null,
    statut_rattachement      text not null default 'non_rattache'
                                check (statut_rattachement in ('non_rattache', 'auto_suggere', 'valide', 'manuel')),
    nom_parcelle              text,               -- alimenté via parcelles ou saisie libre
    culture                   text,               -- alimenté via parcelles ou saisie libre
    culture_n1                text,               -- alimenté via parcelles ou saisie libre
    culture_n2                text,               -- alimenté via parcelles ou saisie libre
    surface                   numeric(10,2),      -- alimenté via parcelles ou saisie libre
    geom                      geometry(Point, 2154) not null,   -- position prévue
    type_analyse              text,
    created_at                timestamptz not null default now()
);

create index if not exists idx_commandes_geom
    on commandes using gist (geom);

create index if not exists idx_commandes_parcelle
    on commandes (parcelle_id);

create unique index if not exists idx_id_commandes_logiciel
    on commandes (id_commande_logiciel)
    where id_commande_logiciel is not null;
-- ------------------------------------------------------------
-- Table Prélèvement_sol
-- ------------------------------------------------------------

create table if not exists prelevements_sol (
    id                  uuid primary key default gen_random_uuid(),
    commande_id         uuid not null unique references commandes(commande_id) on delete cascade,
    geom                geometry(Point, 2154) not null,   -- position réelle au moment du prélèvement
    date_prelevement    date not null default current_date,
    laboratoire         text default 'LabO',
    code_barre          text not null unique,   -- code-barre du prélèvement (différent du code-barre labo)
    statut              text check (statut in ('preleve', 'labo', 'realise')) default 'Prélevé',
    date_labo             date,   -- date de réception au labo
    date_resultat         date,   -- date de réception des résultats
    preleveur           text,
    created_at          timestamptz not null default now()
);

create index if not exists idx_prelevements_geom
    on prelevements_sol using gist (geom);

-- ------------------------------------------------------------
-- Table demande_analyse
-- Pour indiquer qu'une exploitation souhaite x analyses de sol sans que la commande ne soit localisée (ex : phoning)
-- ------------------------------------------------------------

create table if not exists demandes_analyse (
    demande_id              uuid primary key default gen_random_uuid(),
    code_expl               text references exploitation(code_expl) on delete set null,
    campagne                integer not null,
    commentaire             text,
    type_analyse            text,
    prelevement             text check (prelevement in ('Agri', 'CAVAC')),
    statut                  text check (statut in ('A prévoir', 'Terminé')) default 'A prévoir',
    commande_id             uuid references commandes(commande_id) on delete set null,
    created_at              timestamptz not null default now(),
    check (statut <> 'Terminé' or commande_id is not null)
);

create unique index if not exists idx_demandes_analyse_commande_id
    on demandes_analyse (commande_id)
    where commande_id is not null;

-- ------------------------------------------------------------
-- Table RESULTATS_ANALYSE
-- Colonnes fixes pour les paramètres courants d'analyse de sol,
-- + jsonb de secours pour un paramètre spécifique à un labo.
-- Un seul jeu de résultats par prélèvement.
-- ------------------------------------------------------------
create table if not exists resultats_analyse (
    id                      uuid primary key default gen_random_uuid(),
    prelevement_id          uuid not null unique references prelevements_sol(id) on delete cascade,
    numero_echantillon_labo text not null,   -- identifiant attribué par le laboratoire (différent du code_barre terrain)
    ph                      numeric,
    matiere_organique_pct   numeric,
    p2o5_mg_kg              numeric,
    k2o_mg_kg               numeric,
    mgo_mg_kg               numeric,
    cec_meq_100g            numeric,
    autres_resultats        jsonb
);

create index if not exists idx_resultats_prelevement
    on resultats_analyse (prelevement_id);

alter table parcelles          enable row level security;
alter table commandes          enable row level security;
alter table prelevements_sol   enable row level security;
alter table resultats_analyse  enable row level security;
alter table demandes_analyse           enable row level security;
alter table exploitation            enable row level security;
alter table depots             enable row level security;
alter table tae                enable row level security;
alter table ctc                enable row level security;