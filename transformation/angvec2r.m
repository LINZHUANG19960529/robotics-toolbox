%ANGVEC2R Convert angle and vector orientation to a rotation matrix
%
% R = ANGVEC2R(THETA, V) is an orthonormal rotation matrix, R, 
% equivalent to a rotation of THETA about the vector V.
%
% See also eul2r, eulxyz2r.



% Copyright (C) 1993-2014, by Peter I. Corke
%
% This file is part of The Robotics Toolbox for MATLAB (RTB).
% 
% RTB is free software: you can redistribute it and/or modify
% it under the terms of the GNU Lesser General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% 
% RTB is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU Lesser General Public License for more details.
% 
% You should have received a copy of the GNU Leser General Public License
% along with RTB.  If not, see <http://www.gnu.org/licenses/>.
%
% http://www.petercorke.com
function R = angvec2r(theta, k)

%% Init
%#codegen
%$cgargs {zeros(1,1),zeros(3,1)}
assert(isreal(theta) && all(size(theta) == [1 1]), ...
      'angvec2r: alpha = [1x1] (double)');   
assert(isreal(k) && all(size(k) == [3 1]), ...
      'angvec2r: k = [3x1] (double)');  

%% Calculation
	cth = cos(theta);
	sth = sin(theta);
	vth = (1 - cth);
	kx = k(1); ky = k(2); kz = k(3);

        % from Paul's book, p. 28
	R = [
kx*kx*vth+cth      ky*kx*vth-kz*sth   kz*kx*vth+ky*sth
kx*ky*vth+kz*sth   ky*ky*vth+cth      kz*ky*vth-kx*sth
kx*kz*vth-ky*sth   ky*kz*vth+kx*sth   kz*kz*vth+cth
	];
