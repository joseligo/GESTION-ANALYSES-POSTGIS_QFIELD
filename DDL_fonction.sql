-- ------------------------------------------------------------
-- Fonction de pré-remplissage des informations de parcelle dans la table commandes
-- Relie si une parcelle est existante et renseigne le code_expl, la culture, la surface et les cultures N-1 et N-2
-- ------------------------------------------------------------

create or replace function prerenseigner_infos_parcelle()
returns trigger
language plpgsql
as $$
begin
    -- ne recalculer que si parcelle_id est posé ou a changé
    if new.parcelle_id is not null
       and (tg_op = 'INSERT' or new.parcelle_id is distinct from old.parcelle_id) then

        select par.code_expl
          into new.code_expl
          from parcelles par
         where par.id = new.parcelle_id;

    end if;

    return new;
end;
$$;

create trigger trg_commandes_prerenseigner_parcelle
before insert or update of parcelle_id on commandes
for each row
execute function prerenseigner_infos_parcelle();