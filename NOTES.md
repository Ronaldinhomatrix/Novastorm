# Astro Striker: Pegasus Galaxy - Documentação de Criação de Níveis

## Visão Geral

Sistema para criar níveis 3D consistentes sem ajustes manuais de escala, câmera ou física.
Cada nível é configurado manualmente (escala, câmera, física) de forma consistente entre si.

## Arquitetura do Sistema

### Estrutura de um nível

Cada nível segue este fluxo:

1. Criar `level_X.tscn` a partir do `_level_template.tscn`
2. Substituir o nó do cenário pelo asset 3D
3. Ajustar o `Path3D` (curva de voo) e a decoração
4. Configurar manualmente escala/câmera/física para ficar consistente com os outros níveis

## Mapa da Estrutura de Nível (referência rápida)

> Esta é a anatomia padrão de um nível. Entender isto evita confusão ao
> reposicionar a nave, redesenhar a rota ou trocar o cenário.

```
Game (Node3D + game_controller.gd)
├─ WorldEnvironment
├─ DirectionalLight3D
├─ <Cenário>          (ex: GrandCanyon, Mountains1)
├─ <Decoração>        (ex: HighBridge)
└─ FlightPath (Path3D)             ← a curva de voo (selecione para desenhar)
   └─ PathFollower (PathFollow3D + path_follower.gd)
      ├─ Camera3D                  ← offset (0, 0, +33.85669), fov 56.25, current
      └─ Player (instância de player.tscn)  ← posição local (0, 0, -40)
```

### Regras importantes

- **A nave (Player) NÃO vive solta no mundo**: ela é filha do `PathFollower`,
  que desliza sobre a curva do `Path3D`. Por isso o `game_controller.gd` usa
  `node_paths` (`path_follower`, `player`) e os caminhos
  `FlightPath/PathFollower` e `FlightPath/PathFollower/Player`.

- **Para reposicionar a nave no editor**: mova o nó **`FlightPath`** (o Path3D),
  não o `Player` diretamente — o PathFollow3D recalcula a posição local da nave.

- **Para redesenhar a curva de voo**: selecione o nó **`FlightPath`** e use a ferramenta
  **Path** da barra superior do viewport 3D. Não delete o `FlightPath`
  (levaria nave + câmera junto). Para recomeçar do zero, limpe a `curve`
  (Curve3D) mantendo PathFollower/nave/câmera.

- **Velocidade de avanço** da nave é o `forward_speed` no **`PathFollower`**
  (categoria "Movimento ao Longo do Path"). O `speed` no `Player` controla
  apenas a manobra lateral/tela (mouse/teclado/toque), não o avanço na rota.

- **Raiz do nível** chama-se **`Game`** (padrão alinhado entre
  `_level_template.tscn`, `level_1.tscn` e `level_2.tscn`).

## Boas Práticas

### ✅ Fazer
- Manter o `Path3D`/curva de voo como a principal variável manual entre níveis
- Testar a consistência visual entre níveis (posição da nave na tela)
- Configurar escala/câmera/física manualmente e comparar com os outros níveis existentes

### ❌ Evitar
- Ajustar manualmente `ShipModel.scale` de forma inconsistente entre níveis
- Mudar `Camera3D.fov` por nível (a menos que haja motivo artístico)
- Alterar `forward_offset` sem necessidade
- Esquecer de conferir a escala do cenário (causa inconsistência)

## Solução de Problemas

### Nave parece muito grande/pequena
1. Compare a escala do `ShipModel` com os outros níveis
2. Verificar o `forward_offset` do Player na cena

### Câmera "colada" ou "muito longe"
1. Verificar o `offset` Z da `Camera3D` e o `fov`
2. O offset Z deve manter a nave ~40 unidades à frente da câmera

### Colisão não funciona
1. Confirmar que o `BoxShape3D` no `player.tscn` corresponde ao esperado
2. Verificar se o modelo não tem colisores conflitantes

## Próximos Desenvolvimentos
- [ ] Criar validação automática ao carregar nível
- [ ] Adicionar atalhos de editor para ajuste rápido de níveis
- [ ] Documentar exemplos de Path3D para diferentes tipos de nível