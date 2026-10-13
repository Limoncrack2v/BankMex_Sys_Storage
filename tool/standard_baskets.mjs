// Contenido de las despensas estándar (standardBaskets/{basketId}). Es la
// única fuente: lo usan seed_emulators.mjs (emuladores) y
// seed_standard_baskets.mjs (proyecto real). Para cambiar una despensa,
// edítala aquí y vuelve a correr los scripts.
//
// Cada producto: [producto, tipo, cantidad, unidad, días que dura desde la
// entrega]. tipo y unidad son los valores de FoodType y FoodUnit
// (lib/data/models/pantry_item.dart).

export const STANDARD_BASKETS = [
  {
    id: 'despensa-basica',
    name: 'Despensa básica',
    description: 'Abarrotes no perecederos para un hogar de 4 a 5 personas.',
    items: [
      ['Arroz', 'grain', 1, 'kg', 365],
      ['Frijol', 'legume', 1, 'kg', 365],
      ['Lenteja', 'legume', 0.5, 'kg', 365],
      ['Pasta para sopa', 'grain', 4, 'pack', 365],
      ['Harina de maíz', 'grain', 1, 'kg', 180],
      ['Avena', 'grain', 0.4, 'kg', 270],
      ['Aceite vegetal', 'other', 1, 'l', 365],
      ['Atún en lata', 'canned', 2, 'can', 730],
      ['Puré de tomate', 'canned', 2, 'pack', 365],
      ['Leche entera', 'dairy', 2, 'l', 90],
    ],
  },
  {
    id: 'frescos',
    name: 'Frescos',
    description: 'Frutas, verduras y huevo; se entregan junto con la básica.',
    items: [
      ['Jitomate', 'produce', 1, 'kg', 7],
      ['Cebolla', 'produce', 1, 'kg', 14],
      ['Zanahoria', 'produce', 1, 'kg', 14],
      ['Papa', 'produce', 1, 'kg', 21],
      ['Plátano', 'produce', 6, 'piece', 5],
      ['Huevo', 'protein', 12, 'piece', 21],
    ],
  },
];

const str = (value) => ({ stringValue: value });
const int = (value) => ({ integerValue: String(value) });
const dbl = (value) => ({ doubleValue: value });
const ts = (date) => ({ timestampValue: date.toISOString() });
const arr = (values) => ({ arrayValue: values.length ? { values } : {} });
const map = (fields) => ({ mapValue: { fields } });

// Campos de la API REST de Firestore para standardBaskets/{basket.id}.
export function basketFields(basket, updatedAt = new Date()) {
  return {
    name: str(basket.name),
    description: str(basket.description),
    items: arr(
      basket.items.map(([productId, type, quantity, unit, shelfLifeDays]) =>
        map({
          productId: str(productId),
          type: str(type),
          quantity: dbl(quantity),
          unit: str(unit),
          shelfLifeDays: int(shelfLifeDays),
        }),
      ),
    ),
    updatedAt: ts(updatedAt),
  };
}
