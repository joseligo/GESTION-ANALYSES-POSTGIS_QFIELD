-- ============================================================
-- Module de saisie terrain — Prélèvements de sol
-- Schéma PostGIS pour Supabase
-- ============================================================

-- Extension nécessaire (déjà activée)
-- create extension if not exists postgis with schema gis;

-- postgis est dans le schéma "gis", pgcrypto (gen_random_uuid) dans "extensions" :
-- on les ajoute au search_path pour ne pas avoir à préfixer chaque type/fonction
set search_path = public, gis, extensions;

-- ------------------------------------------------------------
-- Table PARCELLES
-- Référentiel parcellaire (existant via plugin Télépac,
-- ou stub minimal si utilisé indépendamment pour l'instant)
-- ------------------------------------------------------------
create table if not exists parcelles (
    id                      uuid primary key default gen_random_uuid(),
    pacage                  text,
    num_ilot                text,
    num_parcelle            text,
    libelle                 text,
    geom                    geometry(Polygon, 2154),
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
-- Table PRELEVEMENTS_SOL
-- Un enregistrement = un point de prélèvement terrain
-- ------------------------------------------------------------
create table if not exists prelevements_sol (
    id                      uuid primary key default gen_random_uuid(),
    parcelle_id             uuid references parcelles(id) on delete set null,
    parcelle_libre          text,               -- repère saisi si parcelle non référencée
    statut_rattachement     text not null default 'non_rattache'
                                check (statut_rattachement in ('non_rattache', 'auto_suggere', 'valide', 'manuel')),
    geom                    geometry(Point, 2154) not null,
    date_prelevement        date not null default current_date,
    type_analyse            text,               -- ex: fertilité, reliquat azoté, physique
    laboratoire             text,
    code_barre              text,               -- code-barres du sac, scanné terrain via QField
    preleveur               text,
    created_at              timestamptz not null default now()
);

create index if not exists idx_prelevements_geom
    on prelevements_sol using gist (geom);

create index if not exists idx_prelevements_parcelle
    on prelevements_sol (parcelle_id);

create unique index if not exists idx_prelevements_code_barre
    on prelevements_sol (code_barre)
    where code_barre is not null;

-- ------------------------------------------------------------
-- Table HORIZONS
-- Plusieurs profondeurs possibles par prélèvement
-- ------------------------------------------------------------
create table if not exists horizons (
    id                  uuid primary key default gen_random_uuid(),
    prelevement_id      uuid not null references prelevements_sol(id) on delete cascade,
    profondeur_debut_cm integer not null,
    profondeur_fin_cm   integer not null,
    check (profondeur_fin_cm > profondeur_debut_cm)
);

create index if not exists idx_horizons_prelevement
    on horizons (prelevement_id);

-- ------------------------------------------------------------
-- Table RESULTATS_ANALYSE
-- Colonnes fixes pour les paramètres courants d'analyse de sol,
-- + jsonb de secours pour un paramètre exotique/spécifique à un labo.
-- Un seul jeu de résultats par prélèvement.
-- ------------------------------------------------------------
create table if not exists resultats_analyse (
    id                      uuid primary key default gen_random_uuid(),
    prelevement_id          uuid not null unique references prelevements_sol(id) on delete cascade,
    numero_echantillon_labo text,   -- identifiant attribué par le laboratoire (différent du code_barre terrain)
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

-- ------------------------------------------------------------
-- Fonction d'import des résultats labo par code-barres
-- Rapproche automatiquement le résultat au prélèvement via le
-- code-barres du sac (si le labo peut le renvoyer dans son fichier).
-- ------------------------------------------------------------
create or replace function importer_resultat_par_code_barre(
    p_code_barre text,
    p_ph numeric default null,
    p_matiere_organique_pct numeric default null,
    p_p2o5_mg_kg numeric default null,
    p_k2o_mg_kg numeric default null,
    p_mgo_mg_kg numeric default null,
    p_cec_meq_100g numeric default null,
    p_numero_echantillon_labo text default null,
    p_autres_resultats jsonb default null
)
returns uuid
language plpgsql
as $$
declare
    v_prelevement_id uuid;
begin
    select id into v_prelevement_id
    from prelevements_sol
    where code_barre = p_code_barre;

    if v_prelevement_id is null then
        raise exception 'Aucun prélèvement trouvé pour le code-barres %', p_code_barre;
    end if;

    insert into resultats_analyse (
        prelevement_id, ph, matiere_organique_pct, p2o5_mg_kg,
        k2o_mg_kg, mgo_mg_kg, cec_meq_100g, numero_echantillon_labo, autres_resultats
    )
    values (
        v_prelevement_id, p_ph, p_matiere_organique_pct, p_p2o5_mg_kg,
        p_k2o_mg_kg, p_mgo_mg_kg, p_cec_meq_100g, p_numero_echantillon_labo, p_autres_resultats
    )
    on conflict (prelevement_id) do update set
        ph = excluded.ph,
        matiere_organique_pct = excluded.matiere_organique_pct,
        p2o5_mg_kg = excluded.p2o5_mg_kg,
        k2o_mg_kg = excluded.k2o_mg_kg,
        mgo_mg_kg = excluded.mgo_mg_kg,
        cec_meq_100g = excluded.cec_meq_100g,
        numero_echantillon_labo = excluded.numero_echantillon_labo,
        autres_resultats = excluded.autres_resultats
    returning prelevement_id into v_prelevement_id;

    return v_prelevement_id;
end;
$$;

-- Usage : select importer_resultat_par_code_barre('CODE123', p_ph => 6.5, ...);

-- ------------------------------------------------------------
-- Fonction de rattachement spatial automatique
-- Relie les prélèvements orphelins (parcelle_id IS NULL) aux
-- parcelles existantes par confinement géométrique
-- ------------------------------------------------------------
create or replace function rattacher_prelevements_orphelins()
returns integer
language plpgsql
as $$
declare
    nb_rattaches integer;
begin
    update prelevements_sol p
    set parcelle_id = par.id,
        statut_rattachement = 'auto_suggere'
    from parcelles par
    where p.parcelle_id is null
      and ST_Contains(par.geom, p.geom);

    get diagnostics nb_rattaches = row_count;
    return nb_rattaches;
end;
$$;

-- Usage : select rattacher_prelevements_orphelins();

-- ------------------------------------------------------------
-- Fonction de validation manuelle d'un rattachement suggéré
-- ------------------------------------------------------------
create or replace function valider_rattachement_parcelle(p_id uuid)
returns void
language sql
as $$
    update prelevements_sol
    set statut_rattachement = 'valide'
    where id = p_id
      and statut_rattachement = 'auto_suggere';
$$;

-- Usage : select valider_rattachement_parcelle('uuid-du-prelevement');

-- ------------------------------------------------------------
-- Table COMMANDES_ANALYSE_SOL
-- Commandes créées dans le logiciel de suivi parcellaire interne.
-- Le point "geom" est la position prévue ; le technicien la
-- confirme/ajuste sur le terrain via QField en validant le statut.
-- ------------------------------------------------------------
create table if not exists commandes_analyse_sol (
    id                      uuid primary key default gen_random_uuid(),
    id_commande_logiciel    text unique,        -- référence de la commande côté logiciel interne
    parcelle_id             uuid references parcelles(id) on delete set null,
    geom                    geometry(Point, 2154) not null,  -- position prévue, ajustable terrain
    type_analyse            text,
    date_commande           date not null default current_date,
    statut                  text not null default 'a_faire'
                                check (statut in ('a_faire', 'realise', 'annule')),
    prelevement_id          uuid references prelevements_sol(id) on delete set null,
    created_at              timestamptz not null default now()
);

create index if not exists idx_commandes_geom
    on commandes_analyse_sol using gist (geom);

create index if not exists idx_commandes_parcelle
    on commandes_analyse_sol (parcelle_id);

create index if not exists idx_commandes_statut
    on commandes_analyse_sol (statut);

-- ------------------------------------------------------------
-- Trigger : validation terrain -> création automatique du prélèvement
-- Quand le statut passe à 'realise' (édition QField), le trigger crée
-- la ligne correspondante dans prelevements_sol et la lie ici, sans
-- ressaisie manuelle.
-- ------------------------------------------------------------
create or replace function valider_commande_analyse()
returns trigger
language plpgsql
as $$
begin
    if new.statut = 'realise'
       and (old.statut is distinct from 'realise')
       and new.prelevement_id is null then

        insert into prelevements_sol (parcelle_id, geom, date_prelevement, type_analyse)
        values (new.parcelle_id, new.geom, current_date, new.type_analyse)
        returning id into new.prelevement_id;

    end if;
    return new;
end;
$$;

drop trigger if exists trg_valider_commande on commandes_analyse_sol;

create trigger trg_valider_commande
    before update on commandes_analyse_sol
    for each row
    execute function valider_commande_analyse();
