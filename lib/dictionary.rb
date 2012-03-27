module ServerTag
    class Dictionary
        def self.lookup(sym)
            {
                :sign_up_for_servertag => %q{Inscrivez-vous sur ServerTag},
                :organization_name => %q{Nom d'Organisation},
                :full_name_of_your_organization => %q{Le nom complet de votre organisation, par exemple "Beep Boop Beep Technologies, L.L.C."},
                :email_address  => %q{Addresse Email},
                :account_owners_email_address => %q{L'addresse email du propriétaire de ce compte. Nous ne le vendrons pas ni l'envoyerons-nous de publicité.},
                :password => %q{Mot de Passe},
                :confirm_password => %q{Confirmation du Mot de Passe},
                :please_make_sure_this_matches => %q{Veuillez assurer que le contenu de ce boîte correspond à celui de celle d'en dessus.},
                :sign_up => %q{Inscrivez-Vous},
                :please_fill_this_in => %q{Veuillez remplir cette boîte}
            }[sym]
        end
    end
end
