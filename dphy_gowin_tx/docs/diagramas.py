"""Símbolos y convenciones de los módulos anteriores."""
import xml.etree.ElementTree as E

class Page:
    def __init__(self, doc, ident, name, title, subtitle, width=1800, height=1700):
        d=E.SubElement(doc,'diagram',id=ident,name=name)
        g=E.SubElement(d,'mxGraphModel',grid='1',gridSize='10',page='1',pageWidth=str(width),pageHeight=str(height),background='#ffffff')
        self.root=E.SubElement(g,'root')
        E.SubElement(self.root,'mxCell',id='0'); E.SubElement(self.root,'mxCell',id='1',parent='0')
        self.text('title',title,50,25,width-100,60,29)
        self.text('subtitle',subtitle,50,95,width-100,70,18)
        self.text('footer','DPHY_GOWIN_TX · RTL · 2026-11-09 | Perfil físico y E/S pendientes de caracterización',50,height-55,width-100,30,15)

    def node(self, ident, label, x,y,w,h,style=''):
        c=E.SubElement(self.root,'mxCell',id=ident,value=label,vertex='1',parent='1',style='html=0;whiteSpace=wrap;fontFamily=Helvetica;fontSize=19;fontColor=#172b4d;fillColor=none;strokeColor=#344563;strokeWidth=2;rounded=0;align=center;verticalAlign=middle;spacing=8;'+style)
        E.SubElement(c,'mxGeometry',x=str(x),y=str(y),width=str(w),height=str(h),**{'as':'geometry'})

    def text(self,ident,label,x,y,w,h,size=19):
        self.node(ident,label,x,y,w,h,f'text;strokeColor=none;fillColor=none;align=left;fontSize={size};spacing=0;')

    def reg(self,ident,label,x,y,w=260,h=140):self.node(ident,label,x,y,w,h)
    def mux(self,ident,label,x,y,w=110,h=160):self.node(ident,label,x,y,w,h,'shape=mxgraph.electrical.abstract.mux2;spacing=1;')
    def gate(self,ident,label,x,y,w=200,h=100):self.node(ident,label,x,y,w,h,'ellipse;')

    def process(self,ident,label,x,y,w=650,h=100,kind='process'):
        styles={'process':'rounded=1;arcSize=12;fillColor=#eaf2fc;strokeColor=#5b7fa6;','decision':'rhombus;fillColor=#fff4d6;strokeColor=#b69a50;spacing=3;','connector':'ellipse;fillColor=#e8edf4;strokeColor=#5c708a;','fault':'rounded=1;arcSize=12;fillColor=#fbe6e6;strokeColor=#a94442;'}
        self.node(ident,label,x,y,w,h,styles[kind])

    def wire(self,src,dst,label='',points=(),control=False,ports='',flow=False):
        c=E.SubElement(self.root,'mxCell',id=f'edge-{len(self.root)}',value=label,edge='1',parent='1',source=src,target=dst,style='edgeStyle=orthogonalEdgeStyle;rounded=0;html=0;endArrow=block;strokeColor=#344563;strokeWidth=2;fontFamily=Helvetica;fontSize=16;labelBackgroundColor=#ffffff;'+('dashed=1;' if control else '')+('exitX=0.5;exitY=1;entryX=0.5;entryY=0;' if flow else 'exitX=1;exitY=0.5;entryX=0;entryY=0.5;')+ports)
        g=E.SubElement(c,'mxGeometry',relative='1',**{'as':'geometry'})
        if points:
            a=E.SubElement(g,'Array',**{'as':'points'})
            for x,y in points:E.SubElement(a,'mxPoint',x=str(x),y=str(y))

    def table(self,ident,rows,x,y,widths,rowheight=55,size=17):
        for i,row in enumerate(rows):
            xx=x
            for j,(value,w) in enumerate(zip(row,widths)):
                self.node(f'{ident}-{i}-{j}',value,xx,y+i*rowheight,w,rowheight,f'fontSize={size};align=left;spacing=8;'+('fontStyle=1;' if i==0 else ''))
                xx+=w

    def chain(self,*ids):
        for a,b in zip(ids,ids[1:]):self.wire(a,b,flow=True)
    def wait(self,ident,x,y,label='No'):
        self.wire(ident,ident,label,[(x,y+65),(x,y-20)],flow=True,ports='exitX=1;exitY=0.5;entryX=0.75;entryY=0;')
