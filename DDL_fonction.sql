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
       and (tg_op = 'INSERT' or old.statut is distinct from 'realise') then

        insert into prelevements_sol (commande_id, geom, date_prelevement)
        values (new.commande_id, new.geom, current_date)
        on conflict (commande_id) do nothing;

    end if;

    return null;  -- ignoré en AFTER
end;
$$;

drop trigger if exists trg_valider_commande on commandes;

create trigger trg_valider_commande
    after insert or update of statut on commandes
    for each row
    execute function valider_commande_analyse();

-- ------------------------------------------------------------
-- Trigger : lien commande - parcelle lorsque une commande est saisie directement depuis la cartographie
--et alimentation automatique des informations de parcelle si lien.
-- renseigne le code_expl, la culture, la surface et les cultures N-1 et N-2
-- ------------------------------------------------------------
create or replace function maj_parcelle_commande()
returns trigger
language plpgsql
as $$
begin
    -- 1. rattachement spatial si le point est posé ou déplacé
    if new.geom is not null
       and (tg_op = 'INSERT' or new.geom is distinct from old.geom) then

        select par.id
          into new.parcelle_id
          from parcelles par
         where st_intersects(par.geom, new.geom)
         limit 1;
    end if;

    -- 2. snapshot si parcelle_id a changé (par l'utilisateur OU par l'étape 1)
    if new.parcelle_id is not null
       and (tg_op = 'INSERT' or new.parcelle_id is distinct from old.parcelle_id) then

        new.statut_rattachement := 'rattachee';

        select par.code_expl, par.culture, par.culture_n_1, par.culture_n_2, par.surface
          into new.code_expl, new.culture, new.culture_n1, new.culture_n2, new.surface
          from parcelles par
         where par.id = new.parcelle_id;

    elsif new.parcelle_id is null then
        new.statut_rattachement := 'non_rattachee';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_commandes_prerenseigner_parcelle on commandes;
drop trigger if exists trg_rattacher_commande_parcelle on commandes;

create or replace trigger trg_commandes_maj_parcelle
    before insert or update of geom, parcelle_id on commandes
    for each row
    execute function maj_parcelle_commande();

