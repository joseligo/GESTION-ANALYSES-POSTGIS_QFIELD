-- =====================================================================
-- DDL DE RÉFÉRENCE — VUES
-- Projet : prélèvements de sol (PostGIS Supabase / QGIS / QField)
-- Version : v1 — 2026-10-03
-- À exécuter APRÈS ddl_tables_261001.sql (v1.1) et
-- ddl_fonctions_triggers_261001.sql
-- =====================================================================
--
-- CONVENTIONS
--   · Préfixe v_ ; vues en lecture seule (cocher « Lecture seule » dans
--     les sources de données du projet QGIS)
--   · WITH (security_invoker = true) : la vue s'exécute avec les droits
--     de l'utilisateur connecté. Sans effet aujourd'hui (utilisateur
--     postgres), indispensable le jour où des comptes individuels avec
--     politiques RLS seront créés (sinon la vue montrerait tout à tous)
--   · Dans QGIS : déclarer la clé à l'ajout de la couche (une vue n'a
--     pas de clé primaire), relations à créer à la main (« Découvrir les
--     relations » ne voit pas les vues)
-- =====================================================================


-- =====================================================================
-- v_exploitations_a_faire — exploitations à visiter par un préleveur
-- =====================================================================
-- · Une ligne par exploitation ayant au moins une commande 'a_faire'
--   en mode 'preleveur' (les commandes agriculteur ne concernent pas le
--   préleveur)
-- · geom = centre des points des commandes à faire (repère de tournée)
-- · Clé QGIS : code_expl
-- · Relation manuelle vue (code_expl) → commandes (code_expl),
--   force Association, pour ouvrir les commandes depuis la fiche
-- · Usage : point d'entrée « tournée » sur QField, et base possible
--   pour le futur tableau de bord
-- =====================================================================
CREATE OR REPLACE VIEW analyses_sol.v_exploitations_a_faire
WITH (security_invoker = true) AS
SELECT e.code_expl,
       e.libelle_exploitation,
       e.commune,
       count(*) AS nb_commandes_a_faire,
       ST_Centroid(ST_Collect(c.geom))::geometry(point, 2154) AS geom
FROM referentiel.exploitation e
JOIN analyses_sol.commandes c ON c.code_expl = e.code_expl
WHERE c.statut = 'a_faire'
  AND c.mode_prelevement = 'preleveur'
GROUP BY e.code_expl, e.libelle_exploitation, e.commune;
