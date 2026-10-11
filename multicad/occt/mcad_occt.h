/* MultiCAD - ponte C para o OpenCascade (fase 8).

   Biblioteca pequena (mcad_occt.dll / libmcad_occt.so) com API C, chamada pelo
   Lazarus (multicad_occt.pas). Cada solido e um "handle" opaco que guarda o
   TopoDS_Shape e o NOME de cada face ("Extrude2/lat:3"): os nomes seguem pelas
   operacoes (historico do OCCT), como no nucleo Pascal.

   Convencoes: vetores em double[3]; referencial do esboco em double[12]
   (origem, X, Y, normal); matriz 3x4 por linhas. Erro: retorno 0/NULL e
   mcad_last_error(). Textos em UTF-8. Nao e reentrante (uma thread). */

#ifndef MCAD_OCCT_H
#define MCAD_OCCT_H

#ifdef _WIN32
#define MCAD_API __declspec(dllexport)
#else
#define MCAD_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void *mcad_shape;
typedef void *mcad_prof;

MCAD_API int mcad_version(void);
MCAD_API const char *mcad_occt_version(void);
MCAD_API const char *mcad_last_error(void);

MCAD_API void mcad_free(mcad_shape s);
MCAD_API mcad_shape mcad_copy(mcad_shape s);

/* perfil plano: lacos de linhas e arcos (o primeiro e o externo) */
MCAD_API mcad_prof mcad_prof_new(const double *frame12);
MCAD_API void mcad_prof_free(mcad_prof p);
MCAD_API void mcad_prof_loop(mcad_prof p);
MCAD_API void mcad_prof_line(mcad_prof p, double x1, double y1, double x2, double y2, const char *name);
MCAD_API void mcad_prof_arc(mcad_prof p, double cx, double cy, double r, double x1, double y1,
  double x2, double y2, int ccw, const char *name);

/* extrusao: inicio em start ao longo de dir, comprimento depth; faces
   "<prefix>/inicio", "<prefix>/fim" e o nome de cada aresta do perfil */
MCAD_API mcad_shape mcad_prism(mcad_prof p, const double *dir3, double start, double depth,
  const char *prefix);
/* revolucao em torno do eixo (ponto, direcao), graus */
MCAD_API mcad_shape mcad_revol(mcad_prof p, const double *pt3, const double *dir3,
  double startDeg, double angleDeg, const char *prefix);

/* booleana: 0 uniao, 1 diferenca (a - b), 2 intersecao */
MCAD_API mcad_shape mcad_bool(mcad_shape a, mcad_shape b, int op);
/* transformacao (3x4 por linhas); renomeia "oldPrefix..." para "newPrefix..." */
MCAD_API mcad_shape mcad_transform(mcad_shape s, const double *m12, const char *oldPrefix,
  const char *newPrefix);

/* filete/chanfro: n pares de faces (nomes); faces novas "<prefix>/<k>" (k = par + 1) */
MCAD_API mcad_shape mcad_fillet(mcad_shape s, int n, const char **faceA, const char **faceB,
  double r, const char *prefix);
MCAD_API mcad_shape mcad_chamfer(mcad_shape s, int n, const char **faceA, const char **faceB,
  double d1, double d2, const char *prefix);
/* casca: faces removidas pelo nome; thickness < 0 para dentro */
MCAD_API mcad_shape mcad_shell(mcad_shape s, int n, const char **faces, double thickness,
  const char *prefix);

/* solido poliedrico a partir de malha (tri = a, b, c, face) */
MCAD_API mcad_shape mcad_from_mesh(int nv, const double *v, int nt, const int *tri, int nf,
  const char **names);

/* consultas */
MCAD_API double mcad_volume(mcad_shape s);
MCAD_API int mcad_valid(mcad_shape s);
MCAD_API int mcad_ncomponents(mcad_shape s);
MCAD_API mcad_shape mcad_component(mcad_shape s, int i);
MCAD_API int mcad_nfaces(mcad_shape s);
MCAD_API const char *mcad_face_name(mcad_shape s, int i);
/* info[9]: tipo (0 plano 1 cilindro 2 cone 3 esfera 4 toro 5 outro), origem(3),
   eixo(3), raio, raio2 (cone: meio angulo em graus) */
MCAD_API int mcad_face_info(mcad_shape s, int i, double *info9);

/* tesselagem: depois leia os buffers (validos ate a proxima chamada) */
MCAD_API int mcad_mesh(mcad_shape s, double deflection, double angleRad);
MCAD_API int mcad_mesh_nverts(void);
MCAD_API const double *mcad_mesh_verts(void);
MCAD_API int mcad_mesh_ntris(void);
MCAD_API const int *mcad_mesh_tris(void);   /* a, b, c, face */

/* STEP (AP214) */
MCAD_API int mcad_step_write(int n, mcad_shape *shapes, const char *file);
MCAD_API mcad_shape mcad_step_read(const char *file, const char *prefix);

#ifdef __cplusplus
}
#endif

#endif
