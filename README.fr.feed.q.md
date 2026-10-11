# Fonctionnement du script feed.q (simulateur de flux kdb+)

Ce script kdb+/q (`feed.q`) est un simulateur de flux en temps réel (feed handler). Il rejoue une journée complète de cotations (quotes) générées par le processus de Hawkes et les propage vers un tickerplant kdb+ standard.

## 1. Initialisation et préparation des données

- **Réutilisation des modèles** : le script intègre les briques de génération définies précédemment : `normal`, `hawkesBranch`, le dictionnaire de paramètres `par`, la durée de session `T` et la fonction `mkQuote`.
- **Flux global ordonné** : il génère les quotes pour l'ensemble des symboles, les rassemble avec `raze`, puis effectue un tri chronologique stable (`day:time xasc ...`) afin de garantir un flux de ticks parfaitement ordonné dans le temps.

## 2. Connexion au tickerplant et paramètres

- **Connexion (`h`)** : le script ouvre une connexion vers un tickerplant à l'écoute sur le port `5010` via `hopen`. Si le tickerplant est injoignable, le processus s'arrête proprement (`exit 1`) en affichant un message d'erreur.
- **Facteur d'accélération (`spd`)** : le script lit les arguments de ligne de commande (`.z.x`) pour récupérer ce facteur de vitesse. Par défaut, il vaut `60f`, ce qui signifie qu'une session boursière de 6h30 est rejouée en 6 minutes et 30 secondes.

## 3. Moteur de rejeu temporel (`.z.ts`)

Le cœur du script repose sur une horloge déclenchée toutes les 100 millisecondes (`\t 100`) grâce au callback `.z.ts` :

1. **Calcul du temps simulé (`tsim`)** : à chaque itération, le temps simulé est obtenu en multipliant le temps réel écoulé depuis le début (`.z.P - t0`) par le coefficient d'accélération `spd`.
2. **Sélection des messages (`bin`)** : la recherche binaire `bin` identifie rapidement l'index du dernier quote dont l'horodatage (`time`) est inférieur ou égal au temps simulé.
3. **Publication asynchrone (`.u.upd`)** : s'il existe de nouveaux événements depuis la dernière position enregistrée (`pos`), le script extrait la tranche correspondante (`value flip day ...`) et l'envoie de manière asynchrone au tickerplant via la commande standard de mise à jour `.u.upd` (`neg[h]`).
4. **Clôture** : une fois tous les ticks de la journée envoyés (`pos >= count day`), le script désactive la minuterie (`system"t 0"`).

Ce type de script est très courant dans les salles de marché pour alimenter des architectures kdb+ de test ou de recette avec un comportement de marché réaliste et contrôlable.
