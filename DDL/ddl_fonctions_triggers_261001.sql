-- =====================================================================
-- DDL DE RÉFÉRENCE — FONCTIONS ET TRIGGERS
-- Projet : prélèvements de sol (PostGIS Supabase / QGIS / QField)
-- Version : v1 — 2026-10-01
-- À exécuter APRÈS ddl_tables_261001.sql
-- =====================================================================
--
-- RÉCAPITULATIF
--   Trigger                               Quand                               Table
--   trg_commandes_rattachement_parcelle   BEFORE INSERT / UPDATE OF geom      analyses_sol.commandes
--   trg_commandes_controle_realise        BEFORE INSERT / UPDATE OF statut    analyses_sol.commandes
--   trg_prelevements_valide_commande      AFTER  INSERT                       analyses_sol.prelevements_sol
--
-- PARCOURS COUVERT
--   1. La commande arrive (import Smag) ou est créée sur le terrain
--      → rattachement à une parcelle + snapshot pour le labo
--   2. Le prélèvement est créé depuis la fiche de la commande
--      → la commande passe en 'realise'
--   3. Toute tentative de 'realise' sans prélèvement est refusée
--
-- Le parcours est indépendant du mode QField : en direct, les triggers
-- s'exécutent immédiatement ; en hors ligne (QFieldCloud), à la synchro,
-- sans que la tablette en dépende pour continuer à travailler.
--
-- Chaque fonction fixe son search_path (pg_catalog, public) : tables
-- qualifiées par leur schéma, PostGIS trouvé dans public, quel que soit
-- le client (QGIS, DBeaver, QFieldCloud).
-- =====================================================================


-- =====================================================================
-- 1. RATTACHEMENT DE LA COMMANDE À UNE PARCELLE + SNAPSHOT
-- =====================================================================
--
-- RÈGLES (parcelle_id / statut_rattachement)
--
--   Création
--     Import Smag, parcelle fournie (cartographiée ou non) → fournie        / logiciel
--     Point dans une parcelle cartographiée                → trouvée        / manuel
--     Point absent ou hors parcelle                        → NULL           / non_rattachee
--
--   Point posé ou déplacé (UPDATE de geom)
--     Dans la même parcelle                                → inchangée      / inchangé
--     Dans une autre parcelle                              → nouvelle       / logiciel_modif si Smag, sinon manuel
--     Hors parcelle, parcelle actuelle NON cartographiée   → conservée      / inchangé
--     Hors parcelle, sinon                                 → NULL           / logiciel_modif si Smag, sinon non_rattachee
--
--   « Smag » = statut précédent 'logiciel' ou 'logiciel_modif' : une fois
--   Smag, une commande le reste, même sortie de toute parcelle.
--
--   La recherche spatiale se limite à la campagne de la commande et
--   ignore les parcelles sans géométrie.
--
-- SNAPSHOT (code_expl, nom_parcelle, culture, culture_n1, culture_n2, surface)
--   Création            → complète uniquement les champs vides
--                         (les valeurs fournies par l'import sont gardées)
--   Changement parcelle → rafraîchi depuis la nouvelle parcelle
--   Parcelle → NULL     → conservé (éventuellement corrigé à la main)
--
-- Prêt pour les commandes sans point (hors v1) : sans geom, pas de
-- recherche spatiale ; poser le point ensuite = un déplacement.
-- =====================================================================
CREATE OR REPLACE FUNCTION analyses_sol.fn_commandes_rattachement_parcelle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_parcelle_id        uuid;
  v_origine_smag       boolean := false;
  v_parcelle_sans_geom boolean := false;
  v_par                record;
BEGIN
  -- A. Import Smag : parcelle fournie
  IF TG_OP = 'INSERT' AND NEW.parcelle_id IS NOT NULL THEN
    NEW.statut_rattachement := 'logiciel';

  -- B. Création sans parcelle, ou point posé / déplacé
  ELSIF TG_OP = 'INSERT' OR NEW.geom IS DISTINCT FROM OLD.geom THEN

    IF TG_OP = 'UPDATE' THEN
      v_origine_smag := OLD.statut_rattachement IN ('logiciel', 'logiciel_modif');
    END IF;

    -- Recherche spatiale (uniquement si un point existe)
    IF NEW.geom IS NOT NULL THEN
      SELECT par.id INTO v_parcelle_id
      FROM parcellaire.parcelles par
      WHERE par.campagne = NEW.campagne
        AND par.geom IS NOT NULL
        AND ST_Intersects(par.geom, NEW.geom)
      LIMIT 1;
    END IF;

    IF v_parcelle_id IS NOT NULL THEN
      -- Point dans une parcelle cartographiée
      IF TG_OP = 'UPDATE' AND v_parcelle_id = OLD.parcelle_id THEN
        NULL;  -- même parcelle : rien ne change
      ELSE
        NEW.parcelle_id := v_parcelle_id;
        NEW.statut_rattachement := CASE WHEN v_origine_smag THEN 'logiciel_modif' ELSE 'manuel' END;
      END IF;

    ELSE
      -- Point absent ou hors parcelle cartographiée
      IF TG_OP = 'UPDATE' AND OLD.parcelle_id IS NOT NULL THEN
        SELECT par.geom IS NULL INTO v_parcelle_sans_geom
        FROM parcellaire.parcelles par
        WHERE par.id = OLD.parcelle_id;
      END IF;

      IF v_parcelle_sans_geom THEN
        NULL;  -- parcelle actuelle non cartographiée : on la garde
      ELSE
        NEW.parcelle_id := NULL;
        NEW.statut_rattachement := CASE WHEN v_origine_smag THEN 'logiciel_modif' ELSE 'non_rattachee' END;
      END IF;
    END IF;
  END IF;

  -- C. Snapshot si une parcelle est posée ou a changé
  IF NEW.parcelle_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.parcelle_id IS DISTINCT FROM OLD.parcelle_id) THEN

    SELECT code_expl, libelle, culture, culture_n1, culture_n2, surface
    INTO v_par
    FROM parcellaire.parcelles
    WHERE id = NEW.parcelle_id;

    IF TG_OP = 'INSERT' THEN
      -- on complète sans écraser ce qui est fourni
      NEW.code_expl    := COALESCE(NEW.code_expl,    v_par.code_expl);
      NEW.nom_parcelle := COALESCE(NEW.nom_parcelle, v_par.libelle);
      NEW.culture      := COALESCE(NEW.culture,      v_par.culture);
      NEW.culture_n1   := COALESCE(NEW.culture_n1,   v_par.culture_n1);
      NEW.culture_n2   := COALESCE(NEW.culture_n2,   v_par.culture_n2);
      NEW.surface      := COALESCE(NEW.surface,      v_par.surface);
    ELSE
      -- changement de parcelle : on rafraîchit
      NEW.code_expl    := v_par.code_expl;
      NEW.nom_parcelle := v_par.libelle;
      NEW.culture      := v_par.culture;
      NEW.culture_n1   := v_par.culture_n1;
      NEW.culture_n2   := v_par.culture_n2;
      NEW.surface      := v_par.surface;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_commandes_rattachement_parcelle
BEFORE INSERT OR UPDATE OF geom ON analyses_sol.commandes
FOR EACH ROW EXECUTE FUNCTION analyses_sol.fn_commandes_rattachement_parcelle();


-- =====================================================================
-- 2. CRÉATION D'UN PRÉLÈVEMENT → COMMANDE RÉALISÉE
-- =====================================================================
-- · Passe la commande liée en 'realise' (si elle ne l'est pas déjà)
-- · Refuse le prélèvement si la commande est annulée
-- · FOR UPDATE : verrouille la commande le temps de la transaction
-- =====================================================================
CREATE OR REPLACE FUNCTION analyses_sol.fn_prelevements_valide_commande()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_statut text;
BEGIN
  SELECT statut INTO v_statut
  FROM analyses_sol.commandes
  WHERE commande_id = NEW.commande_id
  FOR UPDATE;

  IF v_statut = 'annule' THEN
    RAISE EXCEPTION 'Impossible d''ajouter un prélèvement à une commande annulée';
  END IF;

  IF v_statut <> 'realise' THEN
    UPDATE analyses_sol.commandes
    SET statut = 'realise'
    WHERE commande_id = NEW.commande_id;
  END IF;

  RETURN NULL;  -- ignoré en AFTER
END;
$$;

CREATE TRIGGER trg_prelevements_valide_commande
AFTER INSERT ON analyses_sol.prelevements_sol
FOR EACH ROW EXECUTE FUNCTION analyses_sol.fn_prelevements_valide_commande();


-- =====================================================================
-- 3. GARDE-FOU : PAS DE 'realise' SANS PRÉLÈVEMENT
-- =====================================================================
-- · Garantit la règle quel que soit l'outil (QGIS, QField, DBeaver, SQL)
-- · Compatible avec le trigger 2 : quand celui-ci met la commande à jour,
--   le prélèvement existe déjà dans la même transaction.
-- =====================================================================
CREATE OR REPLACE FUNCTION analyses_sol.fn_commandes_controle_realise()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.statut = 'realise' AND NOT EXISTS (
       SELECT 1 FROM analyses_sol.prelevements_sol
       WHERE commande_id = NEW.commande_id) THEN
    RAISE EXCEPTION 'Une commande ne peut passer en « realise » que par la création de son prélèvement';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_commandes_controle_realise
BEFORE INSERT OR UPDATE OF statut ON analyses_sol.commandes
FOR EACH ROW EXECUTE FUNCTION analyses_sol.fn_commandes_controle_realise();
