import struct,sys,os,numpy as np
from PIL import Image
import trimesh
def parse(path):
    b=open(path,'rb').read(); o=4; geos=[]; tex=[]; mats=[]
    while o<len(b):
        tag=b[o:o+4].decode('latin1'); sz=struct.unpack_from('<I',b,o+4)[0]; d=o+8
        if tag=='TEXS':
            tex=[b[d+i*268+4:d+i*268+264].split(b'\0')[0].decode('latin1') for i in range(sz//268)]
        if tag=='MTLS':
            p=d
            while p<d+sz:
                isz=struct.unpack_from('<I',b,p)[0]; q=p+12
                assert b[q:q+4]==b'LAYS'; n=struct.unpack_from('<I',b,q+4)[0]; q+=8
                lsz,fm,sf,tid=struct.unpack_from('<IIII',b,q); mats.append(tid); p+=isz
        if tag=='GEOS':
            p=d
            while p<d+sz:
                isz=struct.unpack_from('<I',b,p)[0]; q=p+4; g={}
                end=p+isz
                while q<end:
                    t=b[q:q+4].decode('latin1')
                    if t in('VRTX','NRMS'):
                        n=struct.unpack_from('<I',b,q+4)[0]; g[t]=np.frombuffer(b,'<f4',n*3,q+8).reshape(-1,3); q+=8+n*12
                    elif t in('PTYP','PCNT','MTGC','MATS'):
                        n=struct.unpack_from('<I',b,q+4)[0]; g[t]=np.frombuffer(b,'<u4',n,q+8); q+=8+n*4
                    elif t=='PVTX':
                        n=struct.unpack_from('<I',b,q+4)[0]; g[t]=np.frombuffer(b,'<u2',n,q+8); q+=8+n*2
                    elif t=='GNDX':
                        n=struct.unpack_from('<I',b,q+4)[0]; q+=8+n
                    elif t=='UVAS':
                        n=struct.unpack_from('<I',b,q+4)[0]; q+=8
                        for _ in range(n):
                            assert b[q:q+4]==b'UVBS'; m=struct.unpack_from('<I',b,q+4)[0]
                            g.setdefault('UV',np.frombuffer(b,'<f4',m*2,q+8).reshape(-1,2)); q+=8+m*8
                    else:
                        # after MATS: materialId, selGroup, selFlags, extent(28), extentsCount, extents
                        mid,sg,sfl=struct.unpack_from('<III',b,q); g['mat']=mid; q+=12+28
                        ec=struct.unpack_from('<I',b,q)[0]; q+=4+ec*28
                geos.append(g); p=end
        o=d+sz
    return geos,tex,mats
def convert(path,out):
    geos,tex,mats=parse(path); base=os.path.dirname(path); meshes=[]
    for g in geos:
        v=g['VRTX'].astype(float); f=g['PVTX'].reshape(-1,3).astype(int)
        # WC3: Z up -> glTF Y up
        v=v[:,[0,2,1]]*np.array([1,1,-1]); 
        uv=g['UV'].copy(); uv[:,1]=1-uv[:,1]
        tid=mats[g['mat']]; img=Image.open(os.path.join(base,tex[tid])).convert('RGBA')
        m=trimesh.Trimesh(v,f[:,[0,2,1]],process=False,visual=trimesh.visual.TextureVisuals(uv=uv,image=img))
        meshes.append(m); print(os.path.basename(path),'verts',len(v),'tris',len(f),'tex',tex[tid],img.size)
    trimesh.Scene(meshes).export(out)
if __name__=='__main__':
    convert(sys.argv[1],sys.argv[2])
