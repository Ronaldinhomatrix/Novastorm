# Diretrizes de Projeto do Pterodon

## Regras de Construção de Cenários e Fases (Level Design)

Sempre que o usuário solicitar a criação de novos cenários, desfiladeiros, túneis ou mapas para o jogo, siga **obrigatoriamente** as seguintes regras:

1. **Malhas Estáticas (Static Mesh Architecture):**
   - **NUNCA** deixe geradores procedurais (`MeshInstance3D` com scripts `@tool` de geração em tempo de execução) ativos rodando no `_ready()` da cena final do nível.
   - O gerador procedural (como `canyon_mesh_generator.gd`) pode ser usado temporariamente como ferramenta de auxílio para criar a malha inicial.
   - Após a geração inicial, a malha DEVE ser congelada ("baked") e salva como um arquivo de recurso estático comprimido em `assets/models/levels/` (ex: `assets/models/levels/stage_X_canyon_mesh.res`).
   - A malha estática deve ser instanciada como um `MeshInstance3D` fixo na cena do nível (ou numa cena `.tscn` reutilizável), desvinculada de scripts procedurais em tempo de execução.

2. **Desacoplamento entre Terreno e Trajetória de Vôo (`FlightPath`):**
   - O cenário 3D DEVE estar preso ("chumbado") em coordenadas estáticas no espaço do mundo.
   - A trajetória da nave/câmera (`FlightPath`) deve ser uma spline independente que passa por dentro ou por cima do cenário fixo.
   - Isso permite que o desenvolvedor/usuário ajuste os pontos da curva (`Curve3D`) no Editor do Godot para alterar a altitude (eixo Y) ou direção (X/Z) da nave, sem que o terreno se mova junto com a curva.

3. **Desempenho e Otimização para Mobile (Android):**
   - Elimine qualquer cálculo de ruído 3D Simplex, loops de vértices ou `SurfaceTool` durante a inicialização (`_ready()`) da fase.
   - Mantenha o tamanho das cenas `.tscn` enxuto (armazenando malhas binárias grandes em arquivos `.res` separados em `assets/models/levels/`), garantindo carregamento instantâneo em aparelhos móveis.
