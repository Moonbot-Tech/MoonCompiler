from pathlib import Path
import json,sys
MASK=(1<<32)-1

def expected(name,n):
    if name.startswith('trip'):return sum((((i+j)&8191)*17)&1023 for i in range(1,n+1) for j in range(4*int(name[4:])))
    if name and name[0].isupper():return negative(name,n)
    if name=='literal_fp':return n*192
    if name=='literal_table':return sum(ord('0123456789abcdef'[(i+j+k)&15]) for i in range(1,n+1) for j in range(64) for k in (0,1))
    if name=='local_table':return sum((j+k)*29+13 for j in range(64) for k in range(3))*n
    a=[(i*747796405+2891336453)&MASK for i in range(8192)]
    if name.startswith('reduction'):
        bound=256 if name=='reduction64' else 16384
        return sum(((i+j)&8191)*17&1023 for i in range(1,n+1) for j in range(bound))
    if name.startswith('matrix'):
        uses=int(name.split('_')[1]) if name.endswith('fields') else 1
        return sum(a[((i&63)*64+j if name=='matrix_row' else j*64+i)+k]
                   for i in range(1,n+1) for j in range(64) for k in range(uses))
    if name=='histogram':return sum((a[(i*17+j)&8191]&255)+1 for i in range(1,n+1) for j in range(256))
    if name=='write_one_base':return (sum(a[:256])*n+256*n*(n+1)//2)&MASK
    if name=='write_two_base':return sum(a[:256])*n&MASK
    if name in ('aliased','nonaliased'):
        b=[0]*8192
        for i in range(1,n+1):
            for j in range(256):
                k=(i+j)&8191;b[k]=(a[k]*(4 if name=='aliased' else 3)+1)&MASK
        return b[(n+7)&8191]
    result=sum((j*17)&1023 for j in range(256))*n
    if name=='pressure_high':
        for k in range(1,7):result^=k*(n*256+1)
    return result

def negative(name,n):
    n=max(n,0)
    data=[i*17+3 for i in range(256)]
    other=[i*19+7 for i in range(256)]
    if name=='CrossUnit':return sum((j+k)*23+11 for j in range(64) for k in range(3))*n
    if name=='OneUse':return sum(data[:64])*n
    if name=='ZeroTrip':return sum(data[j&255]+data[(j+1)&255] for j in range(n))
    if name=='RedefinedBase':return sum(data[j]+other[j]+data[j+1]+other[j+1] for j in range(64))*n
    result=0
    for i in range(n):
        for j in range(64):
            if name!='SideEntry' or not(n&1 and i==0 and j==0):result+=data[j]
            if name=='CallInLoop':data[j]+=3
            if name=='BranchInLoop' and j&1:result+=other[j]
            result+=data[j+1]
    return result

def verify(text):
    count=0
    for line in text.splitlines():
        name,n,result=line.split();want=expected(name,int(n))
        assert int(result)==want,(name,n,result,want)
        count+=1
    return count

if __name__=='__main__':
    for file in sys.argv[1:]:print(file,verify(Path(file).read_text()))
