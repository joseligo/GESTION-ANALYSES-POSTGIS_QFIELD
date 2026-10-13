-- =====================================================================
-- DDL DE RÉFÉRENCE — VUES
-- Projet : prélèvements de sol (PostGIS Supabase / QGIS / QField)
-- Version : v1.1 — 2026-10-13
--   v1.1 : ajout de v_suivi_commandes (tableau de bord de suivi)
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
--   · CREATE OR REPLACE VIEW permet d'AJOUTER des colonnes en fin de
--     liste, pas d'en retirer, renommer ou réordonner : dans ce cas,
--     DROP VIEW puis recréation
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


-- =====================================================================
-- v_suivi_commandes — suivi de réalisation (tableau de bord) (v1.1)
-- =====================================================================
-- · Une ligne par commande (annulées comprises) ; agrégats faits par le
--   tableau de bord (indicateurs, barres par dépôt, carte, bilan
--   agri / préleveur, encart par exploitation, filtres campagne /
--   dépôt / TAE)
-- · etat_suivi :
--     realisee = statut 'realise' (⇔ prélèvement existant, triggers 2 et 3)
--     annulee  = statut 'annule' (gardées pour un éventuel compteur ;
--                avancement calculé sur etat_suivi <> 'annulee')
--     restante = a_faire ou terrain (terrain non prélevé = restante)
--   Le statut du prélèvement (en_attente…) n'est pas pris en compte (v1)
-- · Dépôt = celui de la COMMANDE (pas celui de l'exploitation)
-- · Jointures externes : une commande sans exploitation, TAE ou dépôt
--   reste comptée ; prélèvement unique par commande → pas de doublon
-- · geom en 2154 ; le tableau de bord transforme en 4326 pour Leaflet
-- · Clé : commande_id
-- =====================================================================
CREATE OR REPLACE VIEW analyses_sol.v_suivi_commandes
WITH (security_invoker = true) AS
SELECT c.commande_id,
       c.id_commande_logiciel,
       c.campagne,
       c.statut,
       CASE c.statut
         WHEN 'realise' THEN 'realisee'
         WHEN 'annule'  THEN 'annulee'
         ELSE 'restante'
       END                                   AS etat_suivi,
       c.mode_prelevement,
       c.type_analyse,
       c.depot,
       d.nom_site                            AS nom_depot,
       c.code_expl,
       e.libelle_exploitation,
       e.tae,
       t.prenom_tech || ' ' || t.nom_tech    AS nom_tae,
       c.nom_parcelle,
       c.culture,
       c.surface,
       c.created_at::date                    AS date_commande,
       p.date_prelevement,
       c.geom
FROM analyses_sol.commandes c
LEFT JOIN referentiel.exploitation      e ON e.code_expl   = c.code_expl
LEFT JOIN referentiel.tae               t ON t.code_tech   = e.tae
LEFT JOIN referentiel.depots            d ON d.code_site   = c.depot
LEFT JOIN analyses_sol.prelevements_sol p ON p.commande_id = c.commande_id;


-- ---------------------------------------------------------------------
-- Contrôles v_suivi_commandes (validés le 13/10)
-- ---------------------------------------------------------------------
-- 1. Une ligne par commande
-- SELECT (SELECT count(*) FROM analyses_sol.v_suivi_commandes) AS vue,
--        (SELECT count(*) FROM analyses_sol.commandes)         AS table_cmd;
--
-- 2. Réalisée ⇔ prélèvement (doit renvoyer 0)
-- SELECT count(*) FROM analyses_sol.v_suivi_commandes
-- WHERE (etat_suivi = 'realisee') <> (date_prelevement IS NOT NULL);
--
-- 3. Répartition par état et mode de prélèvement
-- SELECT etat_suivi, mode_prelevement, count(*)
-- FROM analyses_sol.v_suivi_commandes
-- GROUP BY 1, 2 ORDER BY 1, 2;
