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
-- Table Sociétaires
-- Liste des sociétaires (agriculteurs)
-- ------------------------------------------------------------
create table if not exists societaires (
    id                      uuid primary key default gen_random_uuid(),
    code_soc              text not null,
    libelle_exploitation                text not null,
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

create unique index if not exists idx_societaires_code_soc
    on societaires (code_soc);

