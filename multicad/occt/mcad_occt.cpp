// MultiCAD - ponte C para o OpenCascade (fase 8). Ver mcad_occt.h.
#include "mcad_occt.h"

#include <string>
#include <vector>
#include <map>
#include <cmath>
#include <cstring>

#include <Standard_Version.hxx>
#include <Standard_Failure.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Shape.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Wire.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Solid.hxx>
#include <TopoDS_Compound.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_ListOfShape.hxx>
#include <TopTools_ShapeMapHasher.hxx>
#include <NCollection_DataMap.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepBuilderAPI_MakeSolid.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepPrimAPI_MakeRevol.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Common.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepFilletAPI_MakeChamfer.hxx>
#include <BRepOffsetAPI_MakeThickSolid.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepLib.hxx>
#include <ShapeFix_Face.hxx>
#include <ShapeFix_Shape.hxx>
#include <Poly_Triangulation.hxx>
#include <gp_Ax1.hxx>
#include <gp_Ax2.hxx>
#include <gp_Ax3.hxx>
#include <gp_Circ.hxx>
#include <gp_Pln.hxx>
#include <gp_Trsf.hxx>
#include <gp_Cylinder.hxx>
#include <gp_Cone.hxx>
#include <gp_Sphere.hxx>
#include <gp_Torus.hxx>
#include <STEPControl_Writer.hxx>
#include <STEPControl_Reader.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <Interface_Static.hxx>
#include <Message.hxx>
#include <Message_Messenger.hxx>
#include <Message_PrinterOStream.hxx>

typedef NCollection_DataMap<TopoDS_Shape, std::string, TopTools_ShapeMapHasher> NameMap;

struct MShape {
  TopoDS_Shape s;
  NameMap names;
  TopTools_IndexedMapOfShape faces;  // ordem das faces (indices 1..N)
  bool indexed = false;
  void index() {
    if (!indexed) {
      faces.Clear();
      TopExp::MapShapes(s, TopAbs_FACE, faces);
      indexed = true;
    }
  }
};

struct Seg {
  bool arc;
  double x1, y1, x2, y2, cx, cy, r;
  bool ccw;
  std::string name;
};

struct Prof {
  gp_Pnt o;
  gp_Dir x, y, n;
  std::vector<std::vector<Seg>> loops;
};

static std::string g_err;
static std::vector<double> g_verts;
static std::vector<int> g_tris;

static void SetErr(const std::string &e) { g_err = e; }

static void SetErrFailure(const char *where, const Standard_Failure &f) {
  std::string m = where;
  m += ": ";
  m += f.GetMessageString() ? f.GetMessageString() : "falha do OpenCascade";
  SetErr(m);
}

static std::string NameOf(const MShape *m, const TopoDS_Shape &f) {
  if (m && m->names.IsBound(f)) return m->names.Find(f);
  return std::string();
}

static MShape *Wrap(const TopoDS_Shape &s) {
  MShape *r = new MShape();
  r->s = s;
  return r;
}

// So os nomes das faces que existem no resultado
static void KeepFacesOf(MShape *r) {
  NameMap keep;
  for (TopExp_Explorer ex(r->s, TopAbs_FACE); ex.More(); ex.Next())
    if (r->names.IsBound(ex.Current()) && !keep.IsBound(ex.Current()))
      keep.Bind(ex.Current(), r->names.Find(ex.Current()));
  r->names = keep;
  r->indexed = false;
}

// Nomes de 'src' passados ao resultado pelo historico da operacao
static void CopyHistory(BRepBuilderAPI_MakeShape &op, const MShape *src, MShape *dst) {
  for (TopExp_Explorer ex(src->s, TopAbs_FACE); ex.More(); ex.Next()) {
    const TopoDS_Shape &f = ex.Current();
    std::string nm = NameOf(src, f);
    if (nm.empty()) continue;
    const TopTools_ListOfShape &mods = op.Modified(f);
    if (mods.IsEmpty()) {
      if (!op.IsDeleted(f) && !dst->names.IsBound(f)) dst->names.Bind(f, nm);
    } else {
      for (TopTools_ListIteratorOfListOfShape it(mods); it.More(); it.Next())
        if (it.Value().ShapeType() == TopAbs_FACE && !dst->names.IsBound(it.Value()))
          dst->names.Bind(it.Value(), nm);
    }
  }
}

static void CopyHistoryAlgo(BRepAlgoAPI_BooleanOperation &op, const MShape *src, MShape *dst) {
  for (TopExp_Explorer ex(src->s, TopAbs_FACE); ex.More(); ex.Next()) {
    const TopoDS_Shape &f = ex.Current();
    std::string nm = NameOf(src, f);
    if (nm.empty()) continue;
    const TopTools_ListOfShape &mods = op.Modified(f);
    if (mods.IsEmpty()) {
      if (!op.IsDeleted(f) && !dst->names.IsBound(f)) dst->names.Bind(f, nm);
    } else {
      for (TopTools_ListIteratorOfListOfShape it(mods); it.More(); it.Next())
        if (it.Value().ShapeType() == TopAbs_FACE && !dst->names.IsBound(it.Value()))
          dst->names.Bind(it.Value(), nm);
    }
  }
}

static void NameUnnamed(MShape *r, const std::string &prefix) {
  int k = 0;
  for (TopExp_Explorer ex(r->s, TopAbs_FACE); ex.More(); ex.Next())
    if (!r->names.IsBound(ex.Current())) r->names.Bind(ex.Current(), prefix + "/x" + std::to_string(++k));
}

static gp_Pnt P3(const Prof *p, double x, double y, const gp_Vec &off) {
  gp_XYZ v = p->o.XYZ() + p->x.XYZ() * x + p->y.XYZ() * y;
  return gp_Pnt(v + off.XYZ());
}

// Monta a face do perfil (deslocada por off) e o nome de cada aresta
static bool BuildFace(const Prof *p, const gp_Vec &off, TopoDS_Face &face,
                      std::vector<std::pair<TopoDS_Edge, std::string>> &edges) {
  edges.clear();
  if (p->loops.empty() || p->loops[0].empty()) {
    SetErr("perfil vazio");
    return false;
  }
  gp_Pnt org = p->o.Translated(off);
  gp_Pln pln(gp_Ax3(org, p->n, p->x));
  BRepBuilderAPI_MakeFace mf(pln);
  for (size_t L = 0; L < p->loops.size(); L++) {
    BRepBuilderAPI_MakeWire mw;
    for (const Seg &s : p->loops[L]) {
      TopoDS_Edge e;
      gp_Pnt a = P3(p, s.x1, s.y1, off), b = P3(p, s.x2, s.y2, off);
      if (!s.arc) {
        if (a.Distance(b) < 1e-9) continue;
        BRepBuilderAPI_MakeEdge me(a, b);
        if (!me.IsDone()) { SetErr("linha inválida no perfil"); return false; }
        e = me.Edge();
      } else {
        gp_Pnt c = P3(p, s.cx, s.cy, off);
        gp_Dir ax = s.ccw ? p->n : p->n.Reversed();
        gp_Circ circ(gp_Ax2(c, ax, p->x), s.r);
        if (a.Distance(b) < 1e-9) {
          BRepBuilderAPI_MakeEdge me(circ);
          if (!me.IsDone()) { SetErr("círculo inválido no perfil"); return false; }
          e = me.Edge();
        } else {
          BRepBuilderAPI_MakeEdge me(circ, a, b);
          if (!me.IsDone()) { SetErr("arco inválido no perfil"); return false; }
          e = me.Edge();
        }
      }
      mw.Add(e);
      if (!mw.IsDone()) { SetErr("laço do perfil não conecta"); return false; }
      edges.push_back(std::make_pair(TopoDS::Edge(mw.Edge()), s.name));
    }
    if (!mw.IsDone()) { SetErr("laço do perfil vazio"); return false; }
    TopoDS_Wire w = mw.Wire();
    if (!w.Closed()) { SetErr("laço do perfil aberto"); return false; }
    mf.Add(w);
  }
  if (!mf.IsDone()) { SetErr("face do perfil inválida"); return false; }
  ShapeFix_Face fix(mf.Face());
  fix.FixOrientation();
  fix.Perform();
  face = fix.Face();
  // as arestas podem ter sido trocadas pelo conserto: refaz pelo mesmo nome
  std::vector<std::pair<TopoDS_Edge, std::string>> fixed;
  for (TopExp_Explorer ex(face, TopAbs_EDGE); ex.More(); ex.Next()) {
    const TopoDS_Edge &e = TopoDS::Edge(ex.Current());
    std::string nm;
    for (auto &pr : edges)
      if (pr.first.IsSame(e)) { nm = pr.second; break; }
    if (nm.empty()) {
      // aresta refeita: acha pela geometria (ponto medio)
      Standard_Real f0, f1;
      Handle(Geom_Curve) cv = BRep_Tool::Curve(e, f0, f1);
      if (!cv.IsNull()) {
        gp_Pnt mid = cv->Value((f0 + f1) / 2);
        double best = 1e9;
        for (auto &pr : edges) {
          Standard_Real g0, g1;
          Handle(Geom_Curve) c2 = BRep_Tool::Curve(pr.first, g0, g1);
          if (c2.IsNull()) continue;
          double d = c2->Value((g0 + g1) / 2).Distance(mid);
          if (d < best) { best = d; nm = pr.second; }
        }
      }
    }
    fixed.push_back(std::make_pair(e, nm));
  }
  edges = fixed;
  return true;
}

// o tradutor STEP escreve estatisticas na saida padrao: silencia
static struct QuietInit {
  QuietInit() {
    Handle(Message_Messenger) m = Message::DefaultMessenger();
    m->RemovePrinters(STANDARD_TYPE(Message_PrinterOStream));
  }
} g_quiet;

extern "C" {

int mcad_version(void) { return 1; }
const char *mcad_occt_version(void) { return OCC_VERSION_COMPLETE; }
const char *mcad_last_error(void) { return g_err.c_str(); }

void mcad_free(mcad_shape s) { delete (MShape *)s; }

mcad_shape mcad_copy(mcad_shape s) {
  if (!s) return nullptr;
  MShape *m = (MShape *)s;
  MShape *r = new MShape();
  r->s = m->s;
  r->names = m->names;
  return r;
}

mcad_prof mcad_prof_new(const double *f) {
  Prof *p = new Prof();
  p->o = gp_Pnt(f[0], f[1], f[2]);
  p->x = gp_Dir(f[3], f[4], f[5]);
  p->y = gp_Dir(f[6], f[7], f[8]);
  p->n = gp_Dir(f[9], f[10], f[11]);
  return p;
}

void mcad_prof_free(mcad_prof p) { delete (Prof *)p; }

void mcad_prof_loop(mcad_prof p) { ((Prof *)p)->loops.emplace_back(); }

void mcad_prof_line(mcad_prof p, double x1, double y1, double x2, double y2, const char *name) {
  Prof *pr = (Prof *)p;
  if (pr->loops.empty()) pr->loops.emplace_back();
  Seg s{};
  s.arc = false; s.x1 = x1; s.y1 = y1; s.x2 = x2; s.y2 = y2; s.name = name ? name : "";
  pr->loops.back().push_back(s);
}

void mcad_prof_arc(mcad_prof p, double cx, double cy, double r, double x1, double y1, double x2,
                   double y2, int ccw, const char *name) {
  Prof *pr = (Prof *)p;
  if (pr->loops.empty()) pr->loops.emplace_back();
  Seg s{};
  s.arc = true; s.cx = cx; s.cy = cy; s.r = r; s.x1 = x1; s.y1 = y1; s.x2 = x2; s.y2 = y2;
  s.ccw = ccw != 0; s.name = name ? name : "";
  pr->loops.back().push_back(s);
}

mcad_shape mcad_prism(mcad_prof p, const double *d, double start, double depth, const char *prefix) {
  try {
    Prof *pr = (Prof *)p;
    gp_Vec dir(d[0], d[1], d[2]);
    if (dir.Magnitude() < 1e-12 || depth <= 0) { SetErr("direção ou profundidade inválida"); return nullptr; }
    dir.Normalize();
    TopoDS_Face face;
    std::vector<std::pair<TopoDS_Edge, std::string>> edges;
    if (!BuildFace(pr, dir * start, face, edges)) return nullptr;
    BRepPrimAPI_MakePrism mk(face, dir * depth);
    if (!mk.IsDone()) { SetErr("extrusão falhou"); return nullptr; }
    MShape *r = Wrap(mk.Shape());
    std::string px = prefix ? prefix : "";
    for (auto &pr2 : edges) {
      const TopTools_ListOfShape &g = mk.Generated(pr2.first);
      for (TopTools_ListIteratorOfListOfShape it(g); it.More(); it.Next())
        if (it.Value().ShapeType() == TopAbs_FACE && !r->names.IsBound(it.Value()))
          r->names.Bind(it.Value(), pr2.second);
    }
    if (!mk.FirstShape().IsNull())
      for (TopExp_Explorer ex(mk.FirstShape(), TopAbs_FACE); ex.More(); ex.Next())
        r->names.Bind(ex.Current(), px + "/inicio");
    if (!mk.LastShape().IsNull())
      for (TopExp_Explorer ex(mk.LastShape(), TopAbs_FACE); ex.More(); ex.Next())
        r->names.Bind(ex.Current(), px + "/fim");
    NameUnnamed(r, px);
    return r;
  } catch (Standard_Failure &f) {
    SetErrFailure("extrusão", f);
    return nullptr;
  } catch (...) {
    SetErr("extrusão: exceção");
    return nullptr;
  }
}

mcad_shape mcad_revol(mcad_prof p, const double *pt, const double *d, double startDeg,
                      double angleDeg, const char *prefix) {
  try {
    Prof *pr = (Prof *)p;
    TopoDS_Face face;
    std::vector<std::pair<TopoDS_Edge, std::string>> edges;
    if (!BuildFace(pr, gp_Vec(0, 0, 0), face, edges)) return nullptr;
    gp_Ax1 ax(gp_Pnt(pt[0], pt[1], pt[2]), gp_Dir(d[0], d[1], d[2]));
    if (std::fabs(startDeg) > 1e-12) {
      gp_Trsf t;
      t.SetRotation(ax, startDeg * M_PI / 180.0);
      BRepBuilderAPI_Transform tr(face, t, true);
      std::vector<std::pair<TopoDS_Edge, std::string>> moved;
      for (auto &e : edges) moved.push_back(std::make_pair(TopoDS::Edge(tr.ModifiedShape(e.first)), e.second));
      edges = moved;
      face = TopoDS::Face(tr.Shape());
    }
    bool full = angleDeg >= 360.0 - 1e-9;
    BRepPrimAPI_MakeRevol mk(face, ax, full ? 2 * M_PI : angleDeg * M_PI / 180.0);
    if (!mk.IsDone()) { SetErr("revolução falhou"); return nullptr; }
    MShape *r = Wrap(mk.Shape());
    std::string px = prefix ? prefix : "";
    for (auto &e : edges) {
      const TopTools_ListOfShape &g = mk.Generated(e.first);
      for (TopTools_ListIteratorOfListOfShape it(g); it.More(); it.Next())
        if (it.Value().ShapeType() == TopAbs_FACE && !r->names.IsBound(it.Value()))
          r->names.Bind(it.Value(), e.second);
    }
    if (!full) {
      if (!mk.FirstShape().IsNull())
        for (TopExp_Explorer ex(mk.FirstShape(), TopAbs_FACE); ex.More(); ex.Next())
          if (!r->names.IsBound(ex.Current())) r->names.Bind(ex.Current(), px + "/inicio");
      if (!mk.LastShape().IsNull())
        for (TopExp_Explorer ex(mk.LastShape(), TopAbs_FACE); ex.More(); ex.Next())
          if (!r->names.IsBound(ex.Current())) r->names.Bind(ex.Current(), px + "/fim");
    }
    NameUnnamed(r, px);
    return r;
  } catch (Standard_Failure &f) {
    SetErrFailure("revolução", f);
    return nullptr;
  } catch (...) {
    SetErr("revolução: exceção");
    return nullptr;
  }
}

mcad_shape mcad_bool(mcad_shape a, mcad_shape b, int op) {
  try {
    MShape *ma = (MShape *)a, *mb = (MShape *)b;
    if (!ma || !mb) { SetErr("booleana sem sólido"); return nullptr; }
    BRepAlgoAPI_BooleanOperation *bop;
    if (op == 0) bop = new BRepAlgoAPI_Fuse();
    else if (op == 1) bop = new BRepAlgoAPI_Cut();
    else bop = new BRepAlgoAPI_Common();
    TopTools_ListOfShape args, tools;
    args.Append(ma->s);
    tools.Append(mb->s);
    bop->SetArguments(args);
    bop->SetTools(tools);
    bop->SetRunParallel(false);
    bop->SetFuzzyValue(1e-6);
    bop->Build();
    if (!bop->IsDone() || bop->HasErrors()) {
      SetErr("booleana do OpenCascade falhou");
      delete bop;
      return nullptr;
    }
    // junta faces coplanares/cocilindricas vizinhas (como no SolidWorks)
    bop->SimplifyResult(Standard_True, Standard_True, 1e-6);
    MShape *r = Wrap(bop->Shape());
    CopyHistoryAlgo(*bop, ma, r);
    CopyHistoryAlgo(*bop, mb, r);
    delete bop;
    KeepFacesOf(r);
    NameUnnamed(r, "Booleana");
    return r;
  } catch (Standard_Failure &f) {
    SetErrFailure("booleana", f);
    return nullptr;
  } catch (...) {
    SetErr("booleana: exceção");
    return nullptr;
  }
}

mcad_shape mcad_transform(mcad_shape s, const double *m, const char *oldPrefix, const char *newPrefix) {
  try {
    MShape *ms = (MShape *)s;
    gp_Trsf t;
    t.SetValues(m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11]);
    BRepBuilderAPI_Transform tr(ms->s, t, true);
    MShape *r = Wrap(tr.Shape());
    std::string op = oldPrefix ? oldPrefix : "", np = newPrefix ? newPrefix : "";
    for (TopExp_Explorer ex(ms->s, TopAbs_FACE); ex.More(); ex.Next()) {
      std::string nm = NameOf(ms, ex.Current());
      if (nm.empty()) continue;
      if (!op.empty() && nm.compare(0, op.size(), op) == 0) nm = np + nm.substr(op.size());
      else if (op.empty() && !np.empty()) nm = np + nm;
      TopoDS_Shape f2 = tr.ModifiedShape(ex.Current());
      if (!r->names.IsBound(f2)) r->names.Bind(f2, nm);
    }
    return r;
  } catch (Standard_Failure &f) {
    SetErrFailure("transformação", f);
    return nullptr;
  }
}

static bool FindEdges(MShape *ms, const std::string &A, const std::string &B,
                      std::vector<TopoDS_Edge> &out, std::vector<TopoDS_Face> &faceA) {
  TopTools_IndexedDataMapOfShapeListOfShape ef;
  TopExp::MapShapesAndAncestors(ms->s, TopAbs_EDGE, TopAbs_FACE, ef);
  bool any = false;
  for (int i = 1; i <= ef.Extent(); i++) {
    const TopTools_ListOfShape &fl = ef.FindFromIndex(i);
    TopoDS_Shape fa, fb;
    for (TopTools_ListIteratorOfListOfShape it(fl); it.More(); it.Next()) {
      std::string nm = NameOf(ms, it.Value());
      if (nm == A && fa.IsNull()) fa = it.Value();
      else if (nm == B && fb.IsNull()) fb = it.Value();
    }
    if (!fa.IsNull() && !fb.IsNull() && !fa.IsSame(fb)) {
      const TopoDS_Edge &e = TopoDS::Edge(ef.FindKey(i));
      if (BRep_Tool::Degenerated(e)) continue;
      out.push_back(e);
      faceA.push_back(TopoDS::Face(fa));
      any = true;
    }
  }
  return any;
}

static mcad_shape Blend(mcad_shape s, int n, const char **fa, const char **fb, double r, double d1,
                        double d2, bool chamfer, const char *prefix) {
  try {
    MShape *ms = (MShape *)s;
    std::string px = prefix ? prefix : "";
    std::vector<std::vector<TopoDS_Edge>> groups(n);
    std::vector<std::vector<TopoDS_Face>> gfaces(n);
    int total = 0;
    std::string missing;
    for (int k = 0; k < n; k++) {
      if (!FindEdges(ms, fa[k], fb[k], groups[k], gfaces[k])) {
        if (missing.empty()) missing = std::string(fa[k]) + " | " + fb[k];
      }
      total += (int)groups[k].size();
    }
    if (total == 0) { SetErr("nenhuma aresta encontrada (" + missing + ")"); return nullptr; }
    TopTools_IndexedMapOfShape used;
    BRepFilletAPI_MakeFillet *mf = nullptr;
    BRepFilletAPI_MakeChamfer *mc = nullptr;
    if (chamfer) mc = new BRepFilletAPI_MakeChamfer(ms->s);
    else mf = new BRepFilletAPI_MakeFillet(ms->s);
    for (int k = 0; k < n; k++)
      for (size_t i = 0; i < groups[k].size(); i++) {
        if (used.Contains(groups[k][i])) continue;
        used.Add(groups[k][i]);
        if (chamfer) {
          if (std::fabs(d1 - d2) < 1e-12) mc->Add(d1, groups[k][i]);
          else mc->Add(d1, d2, groups[k][i], gfaces[k][i]);
        } else mf->Add(r, groups[k][i]);
      }
    BRepBuilderAPI_MakeShape *mk = chamfer ? (BRepBuilderAPI_MakeShape *)mc : (BRepBuilderAPI_MakeShape *)mf;
    mk->Build();
    if (!mk->IsDone()) {
      SetErr(chamfer ? "o OpenCascade não conseguiu fazer o chanfro (valor grande demais?)"
                     : "o OpenCascade não conseguiu fazer o filete (raio grande demais?)");
      delete mf; delete mc;
      return nullptr;
    }
    MShape *res = Wrap(mk->Shape());
    CopyHistory(*mk, ms, res);
    for (int k = 0; k < n; k++)
      for (auto &e : groups[k]) {
        const TopTools_ListOfShape &g = mk->Generated(e);
        for (TopTools_ListIteratorOfListOfShape it(g); it.More(); it.Next())
          if (it.Value().ShapeType() == TopAbs_FACE && !res->names.IsBound(it.Value()))
            res->names.Bind(it.Value(), px + "/" + std::to_string(k + 1));
      }
    delete mf; delete mc;
    KeepFacesOf(res);
    NameUnnamed(res, px + "/canto");
    if (!missing.empty()) SetErr("aresta não encontrada: " + missing); else SetErr("");
    return res;
  } catch (Standard_Failure &f) {
    SetErrFailure(chamfer ? "chanfro" : "filete", f);
    return nullptr;
  } catch (...) {
    SetErr("filete: exceção");
    return nullptr;
  }
}

mcad_shape mcad_fillet(mcad_shape s, int n, const char **fa, const char **fb, double r, const char *prefix) {
  return Blend(s, n, fa, fb, r, 0, 0, false, prefix);
}

mcad_shape mcad_chamfer(mcad_shape s, int n, const char **fa, const char **fb, double d1, double d2,
                        const char *prefix) {
  return Blend(s, n, fa, fb, 0, d1, d2, true, prefix);
}

mcad_shape mcad_shell(mcad_shape s, int n, const char **faces, double thickness, const char *prefix) {
  try {
    MShape *ms = (MShape *)s;
    std::string px = prefix ? prefix : "";
    TopTools_ListOfShape rem;
    for (TopExp_Explorer ex(ms->s, TopAbs_FACE); ex.More(); ex.Next()) {
      std::string nm = NameOf(ms, ex.Current());
      for (int k = 0; k < n; k++)
        if (nm == faces[k]) { rem.Append(ex.Current()); break; }
    }
    BRepOffsetAPI_MakeThickSolid mk;
    mk.MakeThickSolidByJoin(ms->s, rem, thickness, 1e-4, BRepOffset_Skin, Standard_False,
                            Standard_False, GeomAbs_Intersection);
    if (!mk.IsDone()) { SetErr("o OpenCascade não conseguiu fazer a casca (espessura grande demais?)"); return nullptr; }
    MShape *r = Wrap(mk.Shape());
    for (TopExp_Explorer ex(ms->s, TopAbs_FACE); ex.More(); ex.Next()) {
      std::string nm = NameOf(ms, ex.Current());
      if (nm.empty()) continue;
      const TopTools_ListOfShape &mods = mk.Modified(ex.Current());
      if (mods.IsEmpty()) {
        if (!mk.IsDeleted(ex.Current()) && !r->names.IsBound(ex.Current())) r->names.Bind(ex.Current(), nm);
      } else
        for (TopTools_ListIteratorOfListOfShape it(mods); it.More(); it.Next())
          if (!r->names.IsBound(it.Value())) r->names.Bind(it.Value(), nm);
      const TopTools_ListOfShape &gen = mk.Generated(ex.Current());
      for (TopTools_ListIteratorOfListOfShape it(gen); it.More(); it.Next())
        if (it.Value().ShapeType() == TopAbs_FACE && !r->names.IsBound(it.Value()))
          r->names.Bind(it.Value(), px + "/" + nm);
    }
    KeepFacesOf(r);
    NameUnnamed(r, px);
    return r;
  } catch (Standard_Failure &f) {
    SetErrFailure("casca", f);
    return nullptr;
  } catch (...) {
    SetErr("casca: exceção");
    return nullptr;
  }
}

mcad_shape mcad_from_mesh(int nv, const double *v, int nt, const int *tri, int nf, const char **names) {
  try {
    BRepBuilderAPI_Sewing sew(1e-6);
    std::vector<std::pair<TopoDS_Shape, int>> fs;
    for (int i = 0; i < nt; i++) {
      const int *t = tri + 4 * i;
      gp_Pnt a(v[3 * t[0]], v[3 * t[0] + 1], v[3 * t[0] + 2]);
      gp_Pnt b(v[3 * t[1]], v[3 * t[1] + 1], v[3 * t[1] + 2]);
      gp_Pnt c(v[3 * t[2]], v[3 * t[2] + 1], v[3 * t[2] + 2]);
      if (a.Distance(b) < 1e-9 || b.Distance(c) < 1e-9 || a.Distance(c) < 1e-9) continue;
      if (gp_Vec(a, b).Crossed(gp_Vec(a, c)).Magnitude() < 1e-14) continue;
      BRepBuilderAPI_MakePolygon mp(a, b, c, Standard_True);
      if (!mp.IsDone()) continue;
      BRepBuilderAPI_MakeFace mf(mp.Wire(), Standard_True);
      if (!mf.IsDone()) continue;
      sew.Add(mf.Face());
      fs.push_back(std::make_pair(mf.Face(), t[3]));
    }
    sew.Perform();
    TopoDS_Shape sh = sew.SewedShape();
    // todas as cascas (externa e cavidades) num solido so
    BRepBuilderAPI_MakeSolid ms;
    int nsh = 0;
    for (TopExp_Explorer ex(sh, TopAbs_SHELL); ex.More(); ex.Next()) {
      ms.Add(TopoDS::Shell(ex.Current()));
      nsh++;
    }
    if (nsh == 0) { SetErr("malha não forma uma casca fechada"); return nullptr; }
    if (!ms.IsDone()) { SetErr("malha não forma um sólido"); return nullptr; }
    TopoDS_Solid sol = ms.Solid();
    BRepLib::OrientClosedSolid(sol);
    TopoDS_Shape solid = sol;
    GProp_GProps gp;
    BRepGProp::VolumeProperties(solid, gp);
    if (gp.Mass() < 0) solid.Reverse();
    MShape *r = Wrap(solid);
    for (auto &f : fs) {
      std::string nm = (f.second >= 0 && f.second < nf && names[f.second]) ? names[f.second] : "malha";
      TopoDS_Shape m = sew.IsModified(f.first) ? sew.Modified(f.first) : f.first;
      for (TopExp_Explorer ex(m, TopAbs_FACE); ex.More(); ex.Next())
        if (!r->names.IsBound(ex.Current())) r->names.Bind(ex.Current(), nm);
    }
    KeepFacesOf(r);
    NameUnnamed(r, "malha");
    return r;
  } catch (Standard_Failure &f) {
    SetErrFailure("malha para sólido", f);
    return nullptr;
  } catch (...) {
    SetErr("malha para sólido: exceção");
    return nullptr;
  }
}

double mcad_volume(mcad_shape s) {
  try {
    GProp_GProps gp;
    BRepGProp::VolumeProperties(((MShape *)s)->s, gp);
    return gp.Mass();
  } catch (...) {
    return 0;
  }
}

int mcad_valid(mcad_shape s) {
  try {
    BRepCheck_Analyzer an(((MShape *)s)->s);
    return an.IsValid() ? 1 : 0;
  } catch (...) {
    return 0;
  }
}

int mcad_ncomponents(mcad_shape s) {
  int n = 0;
  for (TopExp_Explorer ex(((MShape *)s)->s, TopAbs_SOLID); ex.More(); ex.Next()) n++;
  return n;
}

mcad_shape mcad_component(mcad_shape s, int i) {
  MShape *ms = (MShape *)s;
  int n = 0;
  for (TopExp_Explorer ex(ms->s, TopAbs_SOLID); ex.More(); ex.Next(), n++)
    if (n == i) {
      MShape *r = Wrap(ex.Current());
      r->names = ms->names;
      KeepFacesOf(r);
      return r;
    }
  return nullptr;
}

int mcad_nfaces(mcad_shape s) {
  MShape *m = (MShape *)s;
  m->index();
  return m->faces.Extent();
}

const char *mcad_face_name(mcad_shape s, int i) {
  static std::string buf;
  MShape *m = (MShape *)s;
  m->index();
  if (i < 0 || i >= m->faces.Extent()) return "";
  buf = NameOf(m, m->faces(i + 1));
  return buf.c_str();
}

int mcad_face_info(mcad_shape s, int i, double *o) {
  try {
    MShape *m = (MShape *)s;
    m->index();
    if (i < 0 || i >= m->faces.Extent()) return 0;
    TopoDS_Face f = TopoDS::Face(m->faces(i + 1));
    for (int k = 0; k < 9; k++) o[k] = 0;
    BRepAdaptor_Surface sf(f, Standard_True);
    gp_Ax1 ax;
    switch (sf.GetType()) {
    case GeomAbs_Plane: {
      gp_Pln p = sf.Plane();
      gp_Dir nd = p.Axis().Direction();
      if (f.Orientation() == TopAbs_REVERSED) nd.Reverse();
      o[0] = 0;
      o[1] = p.Location().X(); o[2] = p.Location().Y(); o[3] = p.Location().Z();
      o[4] = nd.X(); o[5] = nd.Y(); o[6] = nd.Z();
      return 1;
    }
    case GeomAbs_Cylinder: {
      gp_Cylinder c = sf.Cylinder();
      ax = c.Axis();
      o[0] = 1; o[7] = c.Radius();
      break;
    }
    case GeomAbs_Cone: {
      gp_Cone c = sf.Cone();
      ax = c.Axis();
      o[0] = 2; o[7] = c.RefRadius(); o[8] = std::fabs(c.SemiAngle()) * 180.0 / M_PI;
      break;
    }
    case GeomAbs_Sphere: {
      gp_Sphere c = sf.Sphere();
      ax = c.Position().Axis();
      o[0] = 3; o[7] = c.Radius();
      break;
    }
    case GeomAbs_Torus: {
      gp_Torus c = sf.Torus();
      ax = c.Axis();
      o[0] = 4; o[7] = c.MajorRadius(); o[8] = c.MinorRadius();
      break;
    }
    default:
      o[0] = 5;
      return 1;
    }
    o[1] = ax.Location().X(); o[2] = ax.Location().Y(); o[3] = ax.Location().Z();
    o[4] = ax.Direction().X(); o[5] = ax.Direction().Y(); o[6] = ax.Direction().Z();
    return 1;
  } catch (...) {
    return 0;
  }
}

int mcad_mesh(mcad_shape s, double defl, double ang) {
  try {
    MShape *m = (MShape *)s;
    m->index();
    g_verts.clear();
    g_tris.clear();
    BRepMesh_IncrementalMesh mesher(m->s, defl, Standard_False, ang, Standard_False);
    for (int i = 1; i <= m->faces.Extent(); i++) {
      TopoDS_Face f = TopoDS::Face(m->faces(i));
      TopLoc_Location loc;
      Handle(Poly_Triangulation) t = BRep_Tool::Triangulation(f, loc);
      if (t.IsNull()) continue;
      int base = (int)(g_verts.size() / 3);
      gp_Trsf tr = loc.Transformation();
      for (int k = 1; k <= t->NbNodes(); k++) {
        gp_Pnt p = t->Node(k).Transformed(tr);
        g_verts.push_back(p.X()); g_verts.push_back(p.Y()); g_verts.push_back(p.Z());
      }
      bool rev = f.Orientation() == TopAbs_REVERSED;
      for (int k = 1; k <= t->NbTriangles(); k++) {
        int a, b, c;
        t->Triangle(k).Get(a, b, c);
        if (rev) std::swap(b, c);
        g_tris.push_back(base + a - 1); g_tris.push_back(base + b - 1); g_tris.push_back(base + c - 1);
        g_tris.push_back(i - 1);
      }
    }
    return 1;
  } catch (Standard_Failure &f) {
    SetErrFailure("tesselagem", f);
    return 0;
  } catch (...) {
    SetErr("tesselagem: exceção");
    return 0;
  }
}

int mcad_mesh_nverts(void) { return (int)(g_verts.size() / 3); }
const double *mcad_mesh_verts(void) { return g_verts.data(); }
int mcad_mesh_ntris(void) { return (int)(g_tris.size() / 4); }
const int *mcad_mesh_tris(void) { return g_tris.data(); }

int mcad_step_write(int n, mcad_shape *shapes, const char *file) {
  try {
    STEPControl_Writer w;
    Interface_Static::SetCVal("write.step.unit", "MM");
    for (int i = 0; i < n; i++)
      if (w.Transfer(((MShape *)shapes[i])->s, STEPControl_AsIs) != IFSelect_RetDone) {
        SetErr("STEP: falha ao converter o sólido");
        return 0;
      }
    if (w.Write(file) != IFSelect_RetDone) { SetErr("STEP: falha ao gravar o arquivo"); return 0; }
    return 1;
  } catch (Standard_Failure &f) {
    SetErrFailure("STEP", f);
    return 0;
  }
}

mcad_shape mcad_step_read(const char *file, const char *prefix) {
  try {
    STEPControl_Reader r;
    if (r.ReadFile(file) != IFSelect_RetDone) { SetErr("STEP: arquivo não pôde ser lido"); return nullptr; }
    r.TransferRoots();
    TopoDS_Shape s = r.OneShape();
    if (s.IsNull()) { SetErr("STEP: nenhum sólido no arquivo"); return nullptr; }
    MShape *m = Wrap(s);
    int k = 0;
    std::string px = prefix ? prefix : "STEP";
    for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next())
      if (!m->names.IsBound(ex.Current())) m->names.Bind(ex.Current(), px + "/f" + std::to_string(++k));
    return m;
  } catch (Standard_Failure &f) {
    SetErrFailure("STEP", f);
    return nullptr;
  }
}

} // extern "C"
