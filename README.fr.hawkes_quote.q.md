# Générateur de Données Synthétiques de Carnet d'Ordres pour kdb+/q

Ce script - hawkes_quote.q - est un générateur de données synthétiques de carnet d'ordres pour $\text{kdb+}/q$. Il simule des cotations $\text{bid}/\text{ask}$ dont les instants d'arrivée suivent un processus de Hawkes (processus auto-excitant), vérifie statistiquement la simulation, écrit une base historique ($\text{HDB}$) partitionnée par date, puis la relit et reconstruit une grille à la milliseconde.

---

## 1. Le Modèle : Processus de Hawkes Exponentiel

L'intensité des arrivées est définie par :
$$\lambda(t) = \mu + \sum_{t_i < t} \alpha \, e^{-\beta(t - t_i)}$$

- $\mu$ : Taux de base (événements/s), représentant les "immigrants" spontanés.
- $\alpha$ : Amplitude de l'excitation ajoutée par chaque événement.
- $\beta$ : Vitesse de décroissance. Ici, $1/\beta = 20\text{ ms}$, ce qui implique une mémoire très courte.
- $n = \alpha/\beta$ : Rapport de branchement, correspondant au nombre moyen d'enfants par événement. La condition $n < 1$ est requise pour assurer la stationnarité.
- **Cadence moyenne :** $\frac{\mu}{1-n}$. Pour AAPL, $n = 40/50 = 0.8$ et $\frac{\mu}{1-n} = \frac{1}{0.2} = 5\text{ événements/s}$.

Le phénomène modélisé est l'effet de grappe (*cluster effect*) : un ordre en amène d'autres dans les millisecondes qui suivent.

---

## 2. Fonctions Utilitaires

### `normal`
Génère une distribution gaussienne à l'aide de la transformée de Box-Muller :
$$Z = \sqrt{-2\ln U_1} \, \cos(2\pi U_2)$$
Cette fonction est utilisée pour le nombre d'immigrants ainsi que pour la marche aléatoire des prix.

### `hawkesBranch[mu;alpha;beta;T]`
Simule le processus par représentation en grappes, sans boucle temporelle événement par événement :
1. **Immigrants :** Le nombre est approché par une loi normale de moyenne $\mu T$, puis tiré uniformément dans $[0, T)$.
2. **Génération par générations :** Pour chaque parent, le nombre d'enfants suit une loi de Poisson de paramètre $n$, tiré par inversion de la $\text{CDF}$ (précalculée sur 40 termes). L'utilisation de $1 + \text{bin}$ permet de compter correctement les valeurs de la $\text{CDF}$ inférieures ou égales à $u$.
3. **Délais :** Chaque enfant arrive après un délai suivant une loi $\text{Exp}(\beta)$, soit $-\ln(U)/\beta$.
4. **Filtrage et récursion :** Les enfants situés hors de $[0, T)$ sont supprimés, et la boucle continue avec la nouvelle génération jusqu'à extinction.
5. `asc res` renvoie les temps triés.

---

## 3. Vérifications Statistiques

- **`ksStat` :** Test de Kolmogorov-Smirnov contre la loi $\text{Exp}(1)$. Si la compensatrice est correcte, ses incréments doivent suivre une loi $\text{Exp}(1)$ (théorème de transformation temporelle ou *time-change theorem*).
- **`acf` :** Autocorrélation à un retard, qui doit être proche de $0$.
- **`checkHawkes` :** Pour chaque symbole :
  - **Compensatrice :** Pour un Hawkes exponentiel, les incréments sont calculés de façon récursive. Avec $A_i = e^{-\beta d_i}(1 + A_{i-1})$, l'incrément s'exprime comme $\mu \, d_i + (\alpha/\beta)(1 - e^{-\beta d_i}) A_{i-1}$.
  - **Fano factor :** Rapport de la variance sur la moyenne des comptages par fenêtre de $10\text{ s}$. La valeur théorique limite est $\frac{1}{(1-n)^2}$ (soit $1/0.04 = 25$ ici), rendant un $\text{Fano} \gg 1$ attendu.
  - **Seuil KS à 5% :** $1.358 / \sqrt{N}$ (valeur critique asymptotique).

Le script affiche ensuite les résultats attendus : moyenne et variance proches de $1$, test KS sous le seuil, autocorrélation faible, et Fano élevé.

---

## 4. Paramètres par Symbole

Une table keyée contient $\mu$, $\alpha$, $\beta$, le prix initial $p_0$, et la volatilité par événement $\sigma$. Les symboles diffèrent par leur activité et leur régime d'excitation (par exemple, TSLA est le plus actif, GOOG le moins).

---

## 5. Génération de la Table `quote`

### `mkQuote[s]`
- Simule les instants $t_k$ (en secondes).
- **Mid :** Marche aléatoire multiplicative $m = \lfloor 100 \, p_0 \exp(\sum \sigma \varepsilon) \rfloor$ en cents (valeur entière).
- **Spread :** Entier aléatoire compris entre $1$ et $3$ cents.
- **Conversion du temps :** `0D09:30:00 + 1e6 * ms` convertit les secondes en millisecondes entières, puis en nanosecondes, puis en `timespan`. La résolution est ainsi fixée à $1\text{ ms}$, tout comme la $\text{HDB}$.
- **Tailles :** Multiples de $100$, compris entre $100$ et $1000$.

Le prix $\text{bid}$ est $0.01 \times m$, et l' $\text{ask}$ est $0.01 \times m + \text{spr}$.

> *Remarque :* L'arrondi du temps à la milliseconde peut engendrer des ex-aequo (plusieurs quotes partageant le même horodatage), ce que vérifie le test des ex-aequo effectué ultérieurement.

---

## 6. Écriture HDB

- `system"rm -rf hdbq"` initialise une base vide.
- `dts` contient 14 dates à partir du $1^{\text{er}}$ janvier 2024, filtrées pour ne conserver que les jours ouvrés (`1 < dts mod 7` exclut les samedis et dimanches, la date $0$ de $q$ étant un samedi).
- `genDay[d]` :
  1. Génère les quotes de tous les symboles et les concatène via `raze`.
  2. Vérifie que le temps est strictement croissant par symbole.
  3. `.Q.dpft[hdb; d; sym; quote]` écrit la partition `hdb/d/quote/`, applique l'attribut partitionné `p` sur `sym`, et enregistre les colonnes.
- `delete quote from \` libère la mémoire.

**Schéma final :** `date` (partition) | `sym` (parted) | `time` (timespan) | `bid` | `ask` | `bsize` | `asize`

---

## 7. Relecture et Contrôles

- `\l hdbq` charge la base en tant que base $\text{kdb+}$.
- `meta quote` doit indiquer que la colonne `time` est de type temporel et que `sym` possède l'attribut `p`.
- Le décompte des ex-aequo par symbole permet de quantifier l'impact de l'arrondi à la milliseconde.

---

## 8. Grille à 1 ms avec *As-Of Join*

- `g` crée une grille de $60\,000$ lignes (soit une minute à raison d'une ligne par milliseconde) à partir de `09:30`.
- `q1` sélectionne les quotes d'AAPL pour la date `d0`.
- `aj[symtime; g; q1]` récupère, pour chaque instant de la grille, la dernière quote connue (*as-of*), représentant la valeur en vigueur à chaque milliseconde.
- `update time: d0 + time` convertit le `timespan` en `timestamp` complet pour l'affichage.
- `show 5 # select from grid where not null bid` affiche les premières lignes valides après la première quote.

---

## Points à Retenir / Vérifications

- **Simulation :** Le modèle est cohérent avec les tests ($n < 1$, agrégation par générations, compensatrice récursive).
- **Précision temporelle :** La résolution de $1\text{ ms}$ génère des ex-aequo, un comportement normal à prendre en compte lors d'analyses fines.
- **Approximation des immigrants :** L'utilisation de la loi normale est valide uniquement si $\mu T$ est grand, ce qui est le cas ici ($\mu T \approx 23\,400$ pour AAPL).
- **Test KS :** La réalisation simultanée de 5 tests augmente la probabilité de faux positifs, comme le souligne le script.
- **Ordre des opérations en $q$ :** Le langage $q$ s'évalue de droite à gauche. Les expressions du type `(1-e)*0f,-1_S` doivent donc être lues en respectant scrupuleusement cette règle.
