# Recette Fuji — module externe pour Lightroom Classic

Affiche dans le panneau Métadonnées de la Bibliothèque les réglages du boîtier de la
photo active, et retrouve le nom de la **recette Fuji** utilisée à la prise de vue.

Le boîtier n'enregistre pas le nom d'une recette : le module lit les réglages dans le
fichier (simulation de film, plage dynamique, balance des blancs et décalages, tons,
couleur, grain, Color Chrome, netteté, bruit, clarté) et les compare aux recettes de
`fuji-recipes.csv`. Les réglages Panasonic, Canon, iPhone et Ricoh GR sont aussi lus.

## Installation

1. Télécharger le dépôt (bouton **Code → Download ZIP**) et le décompresser.
2. Lightroom Classic → Fichier → **Gestionnaire de modules externes** → **Ajouter**.
3. Choisir le dossier `fuji-recipe.lrplugin`.
4. Bibliothèque, panneau Métadonnées : choisir **Appareil photo et recette** dans le
   menu en tête du panneau, puis naviguer entre les photos.

Pour une mise à jour : remplacer le dossier, puis dans le Gestionnaire de modules
externes, sélectionner le module et cliquer sur **Charger de nouveau le module ext.**

## Panneau Métadonnées

Le jeu de métadonnées **Appareil photo et recette** reprend des champs de Lightroom
(fichier, modèle, objectif, exposition, ISO, focale, date) puis quatre champs du module :

- **Recette** : nom de la recette Fuji, ou « Recette non identifiée ».
- **Réglages** : sur Fuji, simulation, plage dynamique ou priorité DR et balance des
  blancs, puis tons, couleur et netteté. Sur Panasonic et Canon : style, balance des
  blancs, mode et ajustements. Sur iPhone : le mode ; sur Ricoh : la balance des
  blancs et le mode.
- **Détails** : source de la recette, ou recette la plus proche et réglages qui
  diffèrent ; grain, Color Chrome, bruit, clarté…
- **Remarque** : lecture dans le RAF associé, ou raison pour laquelle les réglages
  n'ont pas été lus.

Les champs se remplissent quand une photo devient la photo active. Pour remplir d'un
coup un dossier ou une collection : sélectionner les photos, puis Bibliothèque →
Module externe - Extras → **Renseigner le panneau Métadonnées pour la sélection…**
(sans sélection, toutes les photos du film fixe). **Recette** et **Réglages** servent
ensuite de critères dans les collections dynamiques et la recherche texte, et
**Recette** apparaît dans le filtre Métadonnées de la Bibliothèque.

## Ajouter ses recettes

Les recettes sont dans `fuji-recipes.csv` (une ligne par recette ; les fichiers de
`recipes/` en sont des copies individuelles). Après modification :

```powershell
python scripts/build_recipes.py
```

régénère `fuji-recipe.lrplugin/Recipes.lua`, puis recharger le module.

Une recette est reconnue quand tous les réglages renseignés dans le CSV sont égaux ;
une case vide n'est pas comparée (tons et plage dynamique avec la priorité DR,
couleur en noir et blanc). Les préréglages fluorescents 1, 2 et 3 et les intensités
Weak et Strong de la priorité DR sont distingués. Si aucune recette ne correspond,
le champ Détails donne la plus proche (trois écarts au plus). Plusieurs recettes
identiques sur les critères comparés s'affichent séparées par « / ».

La plupart des recettes fournies viennent de [Fuji X Weekly](https://fujixweekly.com/)
(Ritchie Roesch et contributeurs) ; la colonne `source` du CSV indique l'origine de
chacune.

## Fonctionnement et limites

- Rien n'est modifié dans les photos, les XMP, ni les métadonnées standard. Le module
  écrit seulement ses quatre champs dans le catalogue, par l'accès réservé aux
  modules externes : pas d'entrée dans l'historique, rien dans les XMP ni dans les
  exports. Un champ n'est réécrit que si sa valeur change. Les champs restent dans le
  catalogue si le module est retiré.
- Fuji : lecture des EXIF/MakerNotes des JPEG et de l'aperçu JPEG des RAF. Si un JPEG
  a perdu ses MakerNotes, le RAF de même nom dans le même dossier est lu à la place.
  Décalages de balance des blancs validés sur X-T5 ; autres générations à vérifier.
  Les réglages N&B WC/MG ne sont pas comparés.
- Panasonic : JPEG uniquement (les RW2 ne sont pas lus). Le codage du bruit varie
  selon les modèles et n'est validé qu'à 0.
- Canon : JPEG uniquement (les CR2 et CR3 ne sont pas lus). Le style Auto ne dit pas
  quels réglages l'appareil a choisis.
- iPhone et Ricoh : JPEG uniquement, mode de prise de vue lu dans l'EXIF standard
  quand l'appareil l'écrit. Les HEIC ne sont pas lus.
- Nikon, Sony et les autres marques : non lus pour l'instant.
- Un original hors ligne garde les valeurs déjà lues ; il est réessayé toutes les
  5 secondes tant que sa photo reste active. Un catalogue occupé est réessayé à la
  vérification suivante. La photo active est vérifiée toutes les 350 ms ; un cache
  de 64 fichiers évite les relectures.
- `?` signifie un réglage absent ou non reconnu ; aucune valeur par défaut n'est
  inventée.
- La recette décrit les réglages du boîtier à la prise de vue, pas le rendu développé
  par Lightroom.

Références : [tags Fujifilm](https://exiftool.org/TagNames/FujiFilm.html),
[préréglages Fuji dans Exiv2](https://github.com/Exiv2/exiv2/blob/main/src/fujimn_int.cpp),
[tags Panasonic](https://exiftool.org/TagNames/Panasonic.html),
[tags Canon](https://exiftool.org/TagNames/Canon.html).

## Tests

Les tests exécutent le code Lua 5.1 du module via [Lupa](https://github.com/scoder/lupa),
sur des fichiers d'exemple générés : aucune photo réelle n'est nécessaire.

```powershell
python -m pip install --target .test-deps lupa
python -m unittest discover -s tests -p "test_*.py"
```

## Licence

[MIT](LICENSE).
