
if( this.args )
    exit

def fact(n){
    (1..n).inject(1){prod,x->prod*x}
}

fact(100)
